--[[   -- https://discord.gg/zqcBffbMZn ]]
function GetAdminPanelConfig()
    return Config.AdminPanel or {}
end

function IsPlayerAdmin(source)
    if not source or source == 0 then
        return false
    end
    local config = GetAdminPanelConfig()
    if not config.Enabled then
        return false
    end
    local ace = config.Ace or "command.fishing"
    return IsPlayerAceAllowed(source, ace)
end

function FormatAdminPlayerName(source)
    local name = GetPlayerName(source) or ("id " .. tostring(source))
    local identifier = (GetPlayeridentifier and GetPlayeridentifier(source)) or source
    return string.format("%s (%s)", name, identifier)
end

function RegisterSafeCallback(name, handler, fallback)
    lib.callback.register(name, function(source, ...)
        local ok, result = pcall(handler, source, ...)
        if not ok then
            print(string.format("^1[qs-fishingjob]^0 %s threw: %s", name, tostring(result)))
            return fallback
        end
        return result
    end)
end

function BuildEventsSnapshot()
    local hotspotConfig = Config.Hotspots or {}
    local tournamentConfig = Config.Tournaments or {}

    function MapZones(zones)
        local result = {}
        for index, zone in ipairs(zones or {}) do
            result[#result + 1] = {
                index = index,
                label = zone.label or ("Zone " .. index),
                radius = zone.radius
            }
        end
        return result
    end

    function MapActive(getActiveFn)
        local active = getActiveFn and getActiveFn()
        if not active then
            return nil
        end
        return {
            zone = active.zone or active.label,
            seconds = active.seconds,
            minutes = active.minutes
        }
    end

    return {
        hotspot = {
            enabled = hotspotConfig.Enabled == true,
            duration = tonumber(hotspotConfig.Duration) or 15,
            zones = MapZones(hotspotConfig.Zones),
            active = MapActive(GetActiveHotspot)
        },
        tournament = {
            enabled = tournamentConfig.Enabled == true,
            duration = tonumber(tournamentConfig.Duration) or 20,
            zones = MapZones(tournamentConfig.Zones),
            active = MapActive(GetActiveTournament)
        }
    }
end

function BuildAdminConfigResponse(path)
    local schema = BuildConfigSchema()
    return {
        ok = true,
        path = path,
        value = path and StoredConfigValue(path) or nil,
        overridden = schema.overridden,
        restartOwed = schema.restartOwed == true
    }
end

RegisterSafeCallback("qs-fisher:admin:load", function(source)
    if not IsPlayerAdmin(source) then
        return { allowed = false }
    end
    local schema = BuildConfigSchema()
    return {
        allowed = true,
        tree = schema.tree,
        overridden = schema.overridden,
        restartOwed = schema.restartOwed == true,
        events = BuildEventsSnapshot()
    }
end, { allowed = false })

RegisterSafeCallback("qs-fisher:admin:events", function(source)
    if not IsPlayerAdmin(source) then
        return { allowed = false }
    end
    return {
        allowed = true,
        events = BuildEventsSnapshot()
    }
end, { allowed = false })

RegisterSafeCallback("qs-fisher:admin:set", function(source, data)
    if not IsPlayerAdmin(source) then
        return { ok = false, reason = "permission" }
    end
    if type(data) ~= "table" or type(data.path) ~= "string" then
        return { ok = false, reason = "bad" }
    end
    local ok, err = SetStoredConfig(data.path, data.value, FormatAdminPlayerName(source))
    if not ok then
        return { ok = false, reason = err, path = data.path }
    end
    if SendWebhook then
        SendWebhook("ConfigChanged", source, "Setting changed", data.path, {
            WebhookField("New value", json.encode(data.value), false)
        })
    end
    return BuildAdminConfigResponse(data.path)
end, { ok = false, reason = "error" })

RegisterSafeCallback("qs-fisher:admin:reset", function(source, data)
    if not IsPlayerAdmin(source) then
        return { ok = false, reason = "permission" }
    end
    if type(data) ~= "table" then
        return { ok = false, reason = "bad" }
    end
    if data.all == true then
        local restoredCount = ResetAllStoredConfig()
        if SendWebhook then
            SendWebhook("ConfigChanged", source, "Every setting reset", nil, {
                WebhookField("Settings restored", restoredCount)
            })
        end
        local res = BuildAdminConfigResponse(nil)
        res.restored = restoredCount
        res.reload = true
        return res
    end
    if type(data.path) ~= "string" then
        return { ok = false, reason = "bad" }
    end
    local ok, err = ResetStoredConfig(data.path)
    if not ok then
        return { ok = false, reason = err, path = data.path }
    end
    if SendWebhook then
        SendWebhook("ConfigChanged", source, "Setting reset to the file", data.path)
    end
    return BuildAdminConfigResponse(data.path)
end, { ok = false, reason = "error" })

RegisterSafeCallback("qs-fisher:admin:event", function(source, data)
    if not IsPlayerAdmin(source) then
        return { ok = false, reason = "permission" }
    end
    if type(data) ~= "table" then
        return { ok = false, reason = "bad" }
    end
    local what = tostring(data.what or "")
    local action = tostring(data.action or "")

    function HandleEventAction(zones, startFn, stopFn)
        if not startFn then
            return { ok = false, reason = "missing" }
        end
        if action == "stop" then
            local stopped = stopFn()
            return { ok = (stopped == true), reason = "notrunning" }
        end
        if action == "start" then
            local zoneList = zones or {}
            local zoneIndex = tonumber(data.zone) or 0
            local targetZone = zoneList[zoneIndex]
            local minutes = math.min(math.max(tonumber(data.minutes) or 0, 1), 1440)
            local started = startFn(targetZone, minutes)
            return {
                ok = (started == true),
                reason = started and "started" or "running"
            }
        end
        return { ok = false, reason = "bad" }
    end

    if what == "hotspot" then
        local zones = (Config.Hotspots and Config.Hotspots.Zones) or {}
        return handleEventAction(zones, StartHotspot, StopHotspot)
    elseif what == "tournament" then
        local zones = (Config.Tournaments and Config.Tournaments.Zones) or {}
        return handleEventAction(zones, StartTournament, StopTournament)
    end
    return { ok = false, reason = "bad" }
end, { ok = false, reason = "error" })

RegisterSafeCallback("qs-fisher:config:pull", function()
    return StoredConfigPayload()
end, {})
--WKLeak_qxOnKJTops0 : https://discord.gg/zqcBffbMZn
--WKLeaks$KOndFTop_2 : https://discord.gg/zqcBffbMZn
--WKLeak_ZXOnd4Top#@ : https://discord.gg/zqcBffbMZn
--WKLeakoaOnzBTopef : https://discord.gg/zqcBffbMZn
--WKLeak-HIOn2aTopA3 : https://discord.gg/zqcBffbMZn
