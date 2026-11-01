--[[   -- https://discord.gg/zqcBffbMZn ]]
local cachedGuideData = nil
local isFetchingGuide = false
local guideBlips = {}
local cachedTournamentInfo = nil
local lastTournamentFetch = 0

function IsFeatureEnabled(cfg)
    return (cfg and cfg.Enabled) ~= false
end

local BASICS_STEPS = {
    "GUIDE_STEP_1",
    "GUIDE_STEP_2",
    "GUIDE_STEP_3",
    "GUIDE_STEP_4",
    "GUIDE_STEP_5",
    "GUIDE_STEP_6"
}

local BASICS_TIPS = {
    "GUIDE_TIP_1",
    "GUIDE_TIP_2",
    "GUIDE_TIP_3",
    "GUIDE_TIP_4",
    "GUIDE_TIP_5"
}

function CreateTopic(prefix, lines, shown)
    return {
        prefix = prefix,
        lines = lines,
        shown = shown
    }
end

function GetGuideTabsDefinitions()
    return {
        {
            id = "basics",
            icon = "fish",
            title = "GUIDE_TAB_BASICS",
            intro = "GUIDE_INTRO",
            steps = BASICS_STEPS,
            tips = BASICS_TIPS
        },
        {
            id = "fish",
            icon = "layers",
            title = "GUIDE_TAB_FISH"
        },
        {
            id = "ways",
            icon = "ship",
            title = "GUIDE_TAB_WAYS",
            topics = {
                CreateTopic("GUIDE_WAY_BOAT", 3, IsFeatureEnabled(Config.BoatRental)),
                CreateTopic("GUIDE_WAY_TRAP", 4, IsFeatureEnabled(Config.CrabTraps)),
                CreateTopic("GUIDE_WAY_NET", 4, IsFeatureEnabled(Config.FishingNets)),
                CreateTopic("GUIDE_WAY_SPEAR", 4, IsFeatureEnabled(Config.Speargun))
            }
        },
        {
            id = "cook",
            icon = "fire",
            title = "GUIDE_TAB_COOK",
            topics = {
                CreateTopic("GUIDE_COOK_FIRE", 4, IsFeatureEnabled(Config.Campfire)),
                CreateTopic("GUIDE_COOK_BOAT", 4, IsFeatureEnabled(Config.FoodBoat))
            }
        },
        {
            id = "events",
            icon = "trophy",
            title = "GUIDE_TAB_EVENTS",
            topics = {
                CreateTopic("GUIDE_EV_TOURN", 3, IsFeatureEnabled(Config.Tournaments)),
                CreateTopic("GUIDE_EV_GOLD", 3, IsFeatureEnabled(Config.Hotspots)),
                CreateTopic("GUIDE_EV_CREW", 2, (Config.MaxPartyMembers or 0) > 1),
                CreateTopic("GUIDE_EV_RANK", 2, Config.EnableLeaderboard ~= false)
            }
        }
    }
end

function TranslateString(key)
    local text = Lang(key)
    if text and text ~= key then
        return text
    end
    return nil
end

function TranslateStringList(keyList)
    local result = {}
    for _, key in ipairs(keyList) do
        local translated = TranslateString(key)
        if translated then
            result[#result + 1] = translated
        end
    end
    return result
end

function BuildTopicData(topic)
    if not topic.shown then
        return nil
    end
    local title = TranslateString(topic.prefix .. "_T")
    if not title then
        return nil
    end
    local keys = {}
    for i = 1, topic.lines do
        keys[#keys + 1] = ("%s_%d"):format(topic.prefix, i)
    end
    local lines = TranslateStringList(keys)
    if #lines == 0 then
        return nil
    end
    return {
        title = title,
        lines = lines
    }
end

function BuildTabsData()
    local definitions = GetGuideTabsDefinitions()
    local result = {}

    for _, def in ipairs(definitions) do
        local tab = {
            id = def.id,
            icon = def.icon,
            title = Lang(def.title)
        }

        if def.id == "fish" then
            tab.fish = true
        else
            tab.intro = def.intro and TranslateString(def.intro) or nil
            tab.steps = def.steps and TranslateStringList(def.steps) or nil
            tab.tips = def.tips and TranslateStringList(def.tips) or nil

            if def.topics then
                local topics = {}
                for _, topicDef in ipairs(def.topics) do
                    local built = BuildTopicData(topicDef)
                    if built then
                        topics[#topics + 1] = built
                    end
                end
                tab.topics = topics
            end
        end

        result[#result + 1] = tab
    end

    return result
end

function GetTournamentZones()
    local zones = {}
    local rawZones = (Config.Tournaments and Config.Tournaments.Zones) or {}
    for _, zone in ipairs(rawZones) do
        if zone.coords then
            zones[#zones + 1] = {
                label = zone.label or Lang("GUIDE_TAB_EVENTS"),
                x = zone.coords.x,
                y = zone.coords.y,
                z = zone.coords.z,
                radius = zone.radius or 120.0
            }
        end
    end
    return zones
end

function FetchTournamentInfo()
    local now = GetGameTimer()
    if cachedTournamentInfo and (now - lastTournamentFetch < 5000) then
        return
    end
    lastTournamentFetch = now
    cachedTournamentInfo = lib.callback.await("qs-fisher:getTournamentInfo", 5000)
end

function BuildGuidePayload()
    return {
        fish = (cachedGuideData and cachedGuideData.fish) or {},
        tournament = cachedTournamentInfo,
        tabs = BuildTabsData(),
        zones = GetTournamentZones(),
        ready = (cachedGuideData ~= nil),
        blipsEnabled = (#guideBlips > 0),
        blipsAllowed = (Config.WaterGuide and Config.WaterGuide.Blips == true)
    }
end

function StartFetchGuide()
    if isFetchingGuide then
        return
    end
    isFetchingGuide = true
    CreateThread(function()
        FetchTournamentInfo()
        SendNUIMessage({
            action = "fishingGuideReady",
            guide = BuildGuidePayload()
        })
        if not cachedGuideData then
            local data = lib.callback.await("qs-fisher:getFishingGuide", 10000)
            cachedGuideData = data or { fish = {} }
        end
        isFetchingGuide = false
        SendNUIMessage({
            action = "fishingGuideReady",
            guide = BuildGuidePayload()
        })
    end)
end

function RemoveGuideBlips()
    for _, blip in ipairs(guideBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    guideBlips = {}
end

function CreateGuideBlips()
    RemoveGuideBlips()
    if not (Config.WaterGuide and Config.WaterGuide.Blips) then
        return
    end

    local sprite = (Config.WaterGuide and Config.WaterGuide.BlipSprite) or 317
    local color = (Config.WaterGuide and Config.WaterGuide.BlipColor) or 5
    local zones = GetTournamentZones()

    for _, zone in ipairs(zones) do
        local radiusBlip = AddBlipForRadius(zone.x, zone.y, zone.z, zone.radius)
        SetBlipColour(radiusBlip, color)
        SetBlipAlpha(radiusBlip, 80)
        guideBlips[#guideBlips + 1] = radiusBlip

        local centerBlip = AddBlipForCoord(zone.x, zone.y, zone.z)
        SetBlipSprite(centerBlip, sprite)
        SetBlipDisplay(centerBlip, 4)
        SetBlipScale(centerBlip, 0.85)
        SetBlipColour(centerBlip, color)
        SetBlipAsShortRange(centerBlip, false)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(("%s — %s"):format(Lang("GUIDE_TAB_EVENTS"), zone.label))
        EndTextCommandSetBlipName(centerBlip)
        guideBlips[#guideBlips + 1] = centerBlip
    end
end

function HideFishingGuideBlips()
    if #guideBlips == 0 then
        return
    end
    RemoveGuideBlips()
    SendNUIMessage({
        action = "fishingGuideReady",
        guide = BuildGuidePayload()
    })
end

exports("hideGuideBlips", HideFishingGuideBlips)

RegisterNUICallback("requestFishingGuide", function(data, cb)
    if not (Config.WaterGuide and Config.WaterGuide.Enabled) then
        return cb({
            fish = {},
            tabs = BuildTabsData(),
            zones = {},
            ready = true,
            blipsEnabled = false,
            blipsAllowed = false
        })
    end
    cb(BuildGuidePayload())
    StartFetchGuide()
end)

RegisterNUICallback("toggleFishingBlips", function(data, cb)
    if not (Config.WaterGuide and Config.WaterGuide.Blips) then
        return cb({ enabled = false })
    end
    if data and data.enabled then
        CreateGuideBlips()
    else
        RemoveGuideBlips()
    end
    cb({ enabled = (#guideBlips > 0) })
end)

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    RemoveGuideBlips()
end)
--WKLeak_##On#dTopi$ : https://discord.gg/zqcBffbMZn
--WKLeaksQSOnDQTopDp : https://discord.gg/zqcBffbMZn
--WKLeak-5POnt6Topgi : https://discord.gg/zqcBffbMZn
--WKLeak-mpOnVVTopyC : https://discord.gg/zqcBffbMZn
--WKLeaksfrOnbsTopkU : https://discord.gg/zqcBffbMZn
