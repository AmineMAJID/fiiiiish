--[[   -- https://discord.gg/zqcBffbMZn ]]
local activeHunts = {}
local MIN_DEPTH = 6.0
local MAX_DEPTH = 18.0
local LEASH_DIST = 25.0
local LINE_LENGTH = 100.0
local RESPAWN_MS = 25000
local DETECT_RANGE = 28.0
local ALERT_SECONDS = 8.0
local BODY_SECONDS = 180

function GetSpeargunConfig()
    return Config.Speargun or {}
end

function GetHuntConfig()
    return GetSpeargunConfig().Hunt or {}
end

function GetSyncDistance()
    return 120.0
end

function TriggerNearbyClients(src, includeSrc, eventName, ...)
    local ped = GetPlayerPed(src)
    local srcCoords = GetEntityCoords(ped)
    local maxDist = GetSyncDistance()
    local hasCoords = srcCoords and srcCoords.x and srcCoords.x ~= 0.0

    for _, playerIdStr in ipairs(GetPlayers()) do
        local targetId = tonumber(playerIdStr)
        if targetId and (includeSrc or targetId ~= src) then
            local shouldSend = true
            if hasCoords then
                local targetPed = GetPlayerPed(targetId)
                local targetCoords = GetEntityCoords(targetPed)
                if targetCoords and targetCoords.x and (targetCoords.x ~= 0.0 or targetCoords.y ~= 0.0) then
                    local dist = #(targetCoords - srcCoords)
                    shouldSend = (dist <= maxDist)
                end
            end
            if shouldSend then
                TriggerClientEvent(eventName, targetId, src, ...)
            end
        end
    end
end

RegisterNetEvent("qs-fisher:spearGunDrawn", function(isDrawn)
    TriggerNearbyClients(source, false, "qs-fisher:remoteSpearGun", isDrawn == true)
end)

function PlaySpeargunSound(src)
    if GetResourceState("xsound") ~= "started" then
        return
    end
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    if not coords then
        return
    end

    local soundCfg = GetSpeargunConfig().Sound or {}
    if soundCfg.Enabled == false then
        return
    end

    local soundUrl = ("nui://%s/sounds/%s"):format(GetCurrentResourceName(), "speargun_sound.mp3")
    local soundId = ("speargun_%s_%s"):format(src, math.random(1000, 9999))
    local volume = tonumber(soundCfg.Volume) or 0.35

    pcall(function()
        exports.xsound:PlayUrlPos(-1, soundId, soundUrl, volume, coords)
        exports.xsound:Distance(-1, soundId, 45.0)
    end)
end

RegisterNetEvent("qs-fisher:spearFired", function(originX, originY, originZ, dirX, dirY, dirZ, speed)
    local src = source
    TriggerNearbyClients(
        src,
        false,
        "qs-fisher:remoteSpearFired",
        tonumber(originX) or 0.0,
        tonumber(originY) or 0.0,
        tonumber(originZ) or 0.0,
        tonumber(dirX) or 0.0,
        tonumber(dirY) or 0.0,
        tonumber(dirZ) or 0.0,
        tonumber(speed) or 140
    )
    PlaySpeargunSound(src)
end)

RegisterNetEvent("qs-fisher:spearCleared", function()
    TriggerNearbyClients(source, false, "qs-fisher:remoteSpearCleared")
end)

AddEventHandler("playerDropped", function()
    local src = source
    TriggerClientEvent("qs-fisher:remoteSpearGun", -1, src, false)
    TriggerClientEvent("qs-fisher:remoteSpearCleared", -1, src)
    activeHunts[src] = nil
end)

function GetSharkFishConfig()
    local harvestName = GetSpeargunConfig().Harvest or "shark"
    for _, fish in ipairs(GetOrderedFish()) do
        if fish.name == harvestName then
            return fish
        end
    end
    return nil
end

function SanitizeHuntData(hunt)
    if not hunt then
        return nil
    end
    local huntCfg = GetHuntConfig()
    local speargunCfg = GetSpeargunConfig()

    return {
        zone = hunt.zone.label,
        coords = hunt.zone.coords,
        radius = hunt.zone.radius,
        blip = huntCfg.Blip,
        marker = huntCfg.Marker,
        alive = tonumber(huntCfg.Alive) or 3,
        minDepth = MIN_DEPTH,
        maxDepth = MAX_DEPTH,
        leash = LEASH_DIST,
        lineLength = LINE_LENGTH,
        respawnMs = RESPAWN_MS,
        models = (speargunCfg.Sharks and speargunCfg.Sharks.Models) or {},
        temperaments = (speargunCfg.Sharks and speargunCfg.Sharks.Temperaments) or {},
        detectRange = DETECT_RANGE,
        alertSeconds = ALERT_SECONDS,
        bodySeconds = BODY_SECONDS
    }
end

function StartSharkHunt(playerList)
    if not GetSpeargunConfig().Enabled then
        return false
    end
    local zones = GetHuntConfig().Zones or {}
    if #zones == 0 then
        return false
    end

    local chosenZone = zones[math.random(1, #zones)]
    local huntPayload = SanitizeHuntData({ zone = chosenZone })

    for _, playerId in ipairs(playerList or {}) do
        local targetId = tonumber(playerId)
        if targetId then
            activeHunts[targetId] = {
                zone = chosenZone,
                startedAt = os.time()
            }
            TriggerClientEvent("qs-fisher:sharkHuntStarted", targetId, huntPayload)
        end
    end
    return true
end

function StopSharkHunt(playerId)
    local targetId = tonumber(playerId)
    if not targetId or not activeHunts[targetId] then
        return
    end
    activeHunts[targetId] = nil
    TriggerClientEvent("qs-fisher:sharkHuntEnded", targetId)
end

function PlayerOnSharkHunt(playerId)
    local targetId = tonumber(playerId) or 0
    return activeHunts[targetId] ~= nil
end

lib.callback.register("qs-fisher:getSharkHunt", function(src)
    return SanitizeHuntData(activeHunts[src])
end)

lib.callback.register("qs-fisher:drawSpeargun", function(src)
    local cfg = GetSpeargunConfig()
    if not cfg.Enabled then
        return { ok = false, reason = "disabled" }
    end

    local identifier = GetPlayeridentifier(src)
    if not identifier then
        return { ok = false, reason = "bad" }
    end

    local playerLevel = (PlayersLevels and PlayersLevels[identifier] and PlayersLevels[identifier].level) or 1
    local requiredLevel = tonumber(cfg.RequiredLevel) or 1
    if playerLevel < requiredLevel then
        return { ok = false, reason = "level", level = requiredLevel }
    end

    local speargunItem = cfg.Item or "speargun"
    local gunCount = GetItemCountFromInventory(src, speargunItem) or 0
    if gunCount < 1 then
        return { ok = false, reason = "noitem" }
    end

    local ammoItem = cfg.Ammo or "spear"
    local spearCount = GetItemCountFromInventory(src, ammoItem) or 0

    return {
        ok = true,
        spears = spearCount
    }
end)

lib.callback.register("qs-fisher:useDiveTank", function(src)
    local cfg = GetSpeargunConfig()
    if not cfg.Enabled then
        return { ok = false, reason = "disabled" }
    end

    local identifier = GetPlayeridentifier(src)
    if not identifier then
        return { ok = false, reason = "bad" }
    end

    local tankItem = cfg.Tank or "dive_tank"
    local equipConfig = (Config.FishingEquipment and Config.FishingEquipment[tankItem]) or {}
    local requiredLevel = equipConfig.requiredLevel or 1

    local playerLevel = (PlayersLevels and PlayersLevels[identifier] and PlayersLevels[identifier].level) or 1
    if playerLevel < requiredLevel then
        return { ok = false, reason = "level", level = requiredLevel }
    end

    local tankCount = GetItemCountFromInventory(src, tankItem) or 0
    if tankCount < 1 then
        return { ok = false, reason = "noitem" }
    end

    return { ok = true }
end)

lib.callback.register("qs-fisher:fireSpear", function(src)
    local cfg = GetSpeargunConfig()
    if not cfg.Enabled then
        return { ok = false }
    end

    local ammoItem = cfg.Ammo or "spear"
    local removed = RemoveInventoryItem(src, ammoItem, 1)
    if removed == false then
        return { ok = false, reason = "noammo" }
    end

    local remaining = GetItemCountFromInventory(src, ammoItem) or 0
    return {
        ok = true,
        spears = remaining
    }
end)

lib.callback.register("qs-fisher:harvestShark", function(src)
    local cfg = GetSpeargunConfig()
    if not cfg.Enabled then
        return { ok = false, reason = "disabled" }
    end

    local hunt = activeHunts[src]
    if not hunt then
        return { ok = false, reason = "nohunt" }
    end

    local identifier = GetPlayeridentifier(src)
    if not identifier then
        return { ok = false, reason = "bad" }
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return { ok = false, reason = "bad" }
    end

    local harvestCooldown = math.floor((RESPAWN_MS / 1000) * 0.5)
    local now = os.time()
    if hunt.lastHarvest and (now - hunt.lastHarvest) < harvestCooldown then
        return { ok = false, reason = "toofast" }
    end
    hunt.lastHarvest = now

    local sharkFish = GetSharkFishConfig()
    if not sharkFish then
        return { ok = false, reason = "bad" }
    end

    local stats = RollFishStats(sharkFish.name, {})
    local metadata = nil
    if Config.InventoryMetadata then
        metadata = {
            weight = stats.weight,
            quality = stats.quality,
            trophy = stats.trophy or nil,
            description = ("%.2f kg"):format(stats.weight)
        }
    end

    local success, err = AddInventoryItem(src, sharkFish.name, 1, metadata)
    local missingItem = (success == false and err == "unknown_item") and sharkFish.name or nil

    if success == false and not missingItem then
        return { ok = false, reason = "full" }
    end

    if missingItem and WarnMissingItem then
        WarnMissingItem("the speargun quarry (Config.Speargun.Harvest) in Config.Fish", missingItem)
    end

    local exp = sharkFish.experience or 0
    if AddExperience then
        AddExperience(identifier, exp, src)
    end

    local recoverChance = tonumber(cfg.RecoverChance) or 50
    local recoveredSpear = (math.random(1, 100) <= recoverChance)
    if recoveredSpear then
        AddInventoryItem(src, cfg.Ammo or "spear", 1)
    end

    local isRecord = false
    if RecordCatch then
        isRecord = (RecordCatch(identifier, sharkFish.name, stats, false) == true)
    end

    if UpdateGroupQuestProgress then
        UpdateGroupQuestProgress(src, sharkFish.name, 1)
    end

    if CheckAchievements then
        CheckAchievements(src, identifier)
    end

    return {
        ok = true,
        label = sharkFish.label,
        stats = stats,
        newRecord = isRecord,
        recovered = recoveredSpear,
        missing = missingItem
    }
end)

RegisterNetEvent("qs-fisher:loseSpeargun", function()
    local src = source
    local cfg = GetSpeargunConfig()
    if cfg.Enabled and cfg.LoseGunOnDeath == true then
        RemoveInventoryItem(src, cfg.Item or "speargun", 1)
    end
end)

lib.callback.register("qs-fisher:testSharkHunt", function(src)
    local adminCfg = Config.AdminPanel or {}
    if not adminCfg.Enabled then
        return { ok = false, reason = "tooling" }
    end

    local ace = adminCfg.Ace or "command.fishing"
    if not IsPlayerAceAllowed(src, ace) then
        return { ok = false, reason = "denied", ace = ace }
    end

    if not GetSpeargunConfig().Enabled then
        return { ok = false, reason = "disabled" }
    end

    StopSharkHunt(src)
    if not StartSharkHunt({ src }) then
        return { ok = false, reason = "nozones" }
    end

    if OpenTestRental then
        local tiers = (Config.BoatRental and Config.BoatRental.Tiers) or {}
        OpenTestRental(src, tiers[1])
    end

    return {
        ok = true,
        hunt = SanitizeHuntData(activeHunts[src])
    }
end)
--WKLeak-u#On#ZTopaO : https://discord.gg/zqcBffbMZn
--WKLeakp0OnsfTopG@ : https://discord.gg/zqcBffbMZn
--WKLeak-s1OnUvTopg2 : https://discord.gg/zqcBffbMZn
--WKLeaksbFOnwrTop#I : https://discord.gg/zqcBffbMZn
--WKLeak-D!OnV3Topez : https://discord.gg/zqcBffbMZn
