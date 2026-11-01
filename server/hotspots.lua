--[[   -- https://discord.gg/zqcBffbMZn ]]
local activeHotspot = nil

function GetHotspotConfig()
    return Config.Hotspots or {}
end

function CanPlayerSeeHotspot(source)
    local config = GetHotspotConfig()
    if not config.FishersOnly then
        return true
    end
    if not IsPlayerFisher then
        return true
    end
    return IsPlayerFisher(source) == true
end

function GetEligibleHotspotPlayers()
    local eligiblePlayers = {}
    for _, player in ipairs(GetPlayers()) do
        local src = tonumber(player)
        if src and CanPlayerSeeHotspot(src) then
            eligiblePlayers[#eligiblePlayers + 1] = src
        end
    end
    return eligiblePlayers
end

function BroadcastToHotspotPlayers(eventName, ...)
    for _, playerSrc in ipairs(GetEligibleHotspotPlayers()) do
        TriggerClientEvent(eventName, playerSrc, ...)
    end
end

function IsCoordsInZone(coords, zone)
    if not coords or not zone then
        return false
    end
    local dx = coords.x - zone.coords.x
    local dy = coords.y - zone.coords.y
    return (dx * dx + dy * dy) <= (zone.radius * zone.radius)
end

function GetHotspotPayload()
    if not activeHotspot then
        return nil
    end
    local remainingSeconds = math.max(activeHotspot.endsAt - os.time(), 0)
    return {
        zone = activeHotspot.zone.label,
        coords = activeHotspot.zone.coords,
        radius = activeHotspot.zone.radius,
        blip = GetHotspotConfig().Blip,
        seconds = remainingSeconds
    }
end

function HotspotBoostFor(source)
    if not activeHotspot or not source then
        return nil
    end
    if not CanPlayerSeeHotspot(source) then
        return nil
    end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then
        return nil
    end
    local coords = GetEntityCoords(ped)
    if not IsCoordsInZone(coords, activeHotspot.zone) then
        return nil
    end
    return GetHotspotConfig().Boost or {}
end

function GetActiveHotspot()
    if activeHotspot then
        return GetHotspotPayload()
    end
    return nil
end

function EndActiveHotspot()
    if not activeHotspot then
        return
    end
    local zoneLabel = activeHotspot.zone.label
    activeHotspot = nil
    BroadcastToHotspotPlayers("qs-fisher:hotspotEnded", { zone = zoneLabel })
end

function StartHotspot(zone, duration)
    if activeHotspot then
        return false, "running"
    end
    local config = GetHotspotConfig()
    if not config.Enabled then
        return false, "disabled"
    end
    local zones = config.Zones or {}
    if not zone then
        if #zones == 0 then
            return false, "nozones"
        end
        zone = zones[math.random(1, #zones)]
    end
    if not zone then
        return false, "nozones"
    end
    local durationMins = math.max(tonumber(duration) or tonumber(config.Duration) or 15, 1)
    activeHotspot = {
        zone = zone,
        endsAt = os.time() + (durationMins * 60)
    }
    local payload = GetHotspotPayload()
    payload.minutes = durationMins
    BroadcastToHotspotPlayers("qs-fisher:hotspotStarted", payload)
    return true
end

function StopHotspot()
    if not activeHotspot then
        return false
    end
    EndActiveHotspot()
    return true
end

CreateThread(function()
    while true do
        Wait(1000)
        if activeHotspot and os.time() >= activeHotspot.endsAt then
            EndActiveHotspot()
        end
    end
end)

CreateThread(function()
    local config = GetHotspotConfig()
    local randomConfig = config.Random or {}
    if not config.Enabled or not randomConfig.Enabled then
        return
    end
    local minInterval = math.max(tonumber(randomConfig.MinInterval) or 25, 1)
    local maxInterval = math.max(tonumber(randomConfig.MaxInterval) or minInterval, minInterval)
    while true do
        Wait(math.random(minInterval, maxInterval) * 60000)
        if not activeHotspot then
            StartHotspot()
        end
    end
end)

lib.callback.register("qs-fisher:getHotspot", function(source)
    if not CanPlayerSeeHotspot(source) then
        return nil
    end
    return GetHotspotPayload()
end)
--WKLeaks4MOncYTopLP : https://discord.gg/zqcBffbMZn
--WKLeak#QOnvYTopQZ : https://discord.gg/zqcBffbMZn
--WKLeakn_On_ATopU8 : https://discord.gg/zqcBffbMZn
--WKLeak_3pOn0#Top91 : https://discord.gg/zqcBffbMZn
--WKLeak97Onz3TopZ7 : https://discord.gg/zqcBffbMZn
