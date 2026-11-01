--[[   -- https://discord.gg/zqcBffbMZn ]]
local activeTournament = nil
local tournamentCoordBlip = nil
local tournamentRadiusBlip = nil
local isAllowedTournament = true
local isInsideZone = nil
local QUICK_CLOSE_MS = 2500
local MAX_AUTO_CLOSE_MS = 180000
local isResultsOpen = false
local resultsUserInteracted = false
local resultsHadFocus = false
local resultsSessionId = 0

function CloseTournamentResults()
    if not isResultsOpen then
        return
    end
    isResultsOpen = false
    resultsUserInteracted = false
    resultsSessionId = resultsSessionId + 1
    if resultsHadFocus then
        SetNuiFocus(false, false)
    end
    resultsHadFocus = false
    SendNUIMessage({
        action = "tournamentResultsClose"
    })
end

function OpenTournamentResults(results)
    if isResultsOpen then
        CloseTournamentResults()
    end
    isResultsOpen = true
    resultsUserInteracted = false
    resultsSessionId = resultsSessionId + 1

    resultsHadFocus = not IsNuiFocused()
    if resultsHadFocus then
        SetNuiFocus(true, true)
    end

    SendNUIMessage({
        action = "tournamentResults",
        results = results
    })

    local currentSession = resultsSessionId
    CreateThread(function()
        Wait(QUICK_CLOSE_MS)
        if isResultsOpen and resultsSessionId == currentSession then
            if not resultsUserInteracted then
                return CloseTournamentResults()
            end
        end
        Wait(MAX_AUTO_CLOSE_MS)
        if isResultsOpen and resultsSessionId == currentSession then
            CloseTournamentResults()
        end
    end)
end

function RemoveTournamentBlips()
    if tournamentCoordBlip and DoesBlipExist(tournamentCoordBlip) then
        RemoveBlip(tournamentCoordBlip)
    end
    if tournamentRadiusBlip and DoesBlipExist(tournamentRadiusBlip) then
        RemoveBlip(tournamentRadiusBlip)
    end
    tournamentCoordBlip = nil
    tournamentRadiusBlip = nil
end

function CreateTournamentBlips(tournament)
    RemoveTournamentBlips()
    if not tournament or not tournament.coords then
        return
    end

    local blipCfg = tournament.blip or {}
    tournamentRadiusBlip = AddBlipForRadius(tournament.coords.x, tournament.coords.y, tournament.coords.z, tournament.radius or 100.0)
    SetBlipColour(tournamentRadiusBlip, blipCfg.color or 5)
    SetBlipAlpha(tournamentRadiusBlip, blipCfg.alpha or 128)

    tournamentCoordBlip = AddBlipForCoord(tournament.coords.x, tournament.coords.y, tournament.coords.z)
    SetBlipSprite(tournamentCoordBlip, blipCfg.sprite or 317)
    SetBlipColour(tournamentCoordBlip, blipCfg.color or 5)
    SetBlipScale(tournamentCoordBlip, 0.9)
    SetBlipAsShortRange(tournamentCoordBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(("%s — %s"):format(Lang("TOURNAMENT"), tournament.zone or "?"))
    EndTextCommandSetBlipName(tournamentCoordBlip)
end

function UpdateTournamentHud()
    if not activeTournament or not isInsideZone then
        SendNUIMessage({
            action = "tournament",
            show = false
        })
        return
    end

    SendNUIMessage({
        action = "tournament",
        show = true,
        zone = activeTournament.zone,
        seconds = activeTournament.seconds or 0,
        heaviest = activeTournament.heaviest or {},
        most = activeTournament.most or {}
    })
end

function CheckPlayerInTournamentZone()
    if not activeTournament or not activeTournament.coords or not activeTournament.radius then
        return false
    end
    local coords = GetEntityCoords(PlayerPedId())
    local dx = coords.x - activeTournament.coords.x
    local dy = coords.y - activeTournament.coords.y
    return (dx * dx + dy * dy) <= (activeTournament.radius * activeTournament.radius)
end

function HandleZoneStateChange(notify)
    local inside = CheckPlayerInTournamentZone()
    if inside == isInsideZone then
        return
    end
    local isInitialCheck = (isInsideZone == nil)
    isInsideZone = inside
    UpdateTournamentHud()

    if notify and not isInitialCheck then
        local notifyType = inside and "success" or "info"
        local langKey = inside and "TOURNAMENT_ENTERED" or "TOURNAMENT_LEFT"
        local zoneName = activeTournament and activeTournament.zone or "?"
        CreateNotification("notify", notifyType, Lang(langKey):format(zoneName))
    end
end

CreateThread(function()
    while true do
        if not activeTournament then
            isInsideZone = nil
            Wait(1000)
        else
            HandleZoneStateChange(true)
            Wait(500)
        end
    end
end)

RegisterNetEvent("qs-fisher:tournamentAnnounced", function(data)
    if not isAllowedTournament then
        return
    end
    CreateNotification("notify", "info", Lang("TOURNAMENT_SOON"):format(data.zone or "?", data.minutes or 0))
end)

RegisterNetEvent("qs-fisher:tournamentStarted", function(data)
    if not isAllowedTournament then
        return
    end
    activeTournament = data
    CreateTournamentBlips(data)
    isInsideZone = nil
    HandleZoneStateChange(false)
    CreateNotification("notify", "success", Lang("TOURNAMENT_STARTED"):format(data.zone or "?"))
end)

RegisterNetEvent("qs-fisher:tournamentUpdate", function(data)
    if not isAllowedTournament then
        return
    end
    if not activeTournament then
        activeTournament = data
        CreateTournamentBlips(data)
        isInsideZone = nil
        HandleZoneStateChange(false)
    else
        activeTournament.heaviest = data.heaviest
        activeTournament.most = data.most
        activeTournament.seconds = data.seconds
    end
    UpdateTournamentHud()
end)

RegisterNetEvent("qs-fisher:tournamentEnded", function(results, showResults)
    activeTournament = nil
    isInsideZone = nil
    RemoveTournamentBlips()
    SendNUIMessage({
        action = "tournament",
        show = false
    })

    if showResults then
        OpenTournamentResults(results)
    end

    local topHeaviest = results.heaviest and results.heaviest[1]
    if topHeaviest then
        CreateNotification("notify", "success", Lang("TOURNAMENT_WON_HEAVIEST"):format(topHeaviest.name or "?", topHeaviest.weight or 0))
    end

    local topMost = results.most and results.most[1]
    if topMost then
        CreateNotification("notify", "success", Lang("TOURNAMENT_WON_MOST"):format(topMost.name or "?", topMost.count or 0))
    end
end)

RegisterNUICallback("tournamentWaypoint", function(data, cb)
    cb("ok")
    if not activeTournament or not activeTournament.coords then
        return
    end
    SetNewWaypoint(activeTournament.coords.x, activeTournament.coords.y)
    CreateNotification("notify", "success", Lang("TOURNAMENT_WAYPOINT_SET"))
end)

RegisterNUICallback("tournamentResultsOpen", function(data, cb)
    cb("ok")
    resultsUserInteracted = true
end)

RegisterNUICallback("tournamentResultsClosed", function(data, cb)
    cb("ok")
    CloseTournamentResults()
end)

function ResetTournamentState()
    activeTournament = nil
    isInsideZone = nil
    RemoveTournamentBlips()
    SendNUIMessage({
        action = "tournament",
        show = false
    })
end

function CheckRunningTournament(notify)
    CreateThread(function()
        if notify then
            Wait(5000)
        end
        if not isAllowedTournament then
            return
        end
        local tournament = lib.callback.await("qs-fisher:getTournament", false)
        if not tournament then
            return ResetTournamentState()
        end
        activeTournament = tournament
        CreateTournamentBlips(tournament)
        isInsideZone = nil
        HandleZoneStateChange(false)
        if notify then
            local mins = math.max(math.floor((tournament.seconds or 0) / 60), 1)
            CreateNotification("notify", "info", Lang("TOURNAMENT_ALREADY_RUNNING"):format(tournament.zone or "?", mins))
        end
    end)
end

function OnFisherJobChanged(isFisher)
    if isFisher == nil then
        isAllowedTournament = (Config.Tournaments and Config.Tournaments.FishersOnly) ~= true
    else
        isAllowedTournament = isFisher
    end
    if isAllowedTournament then
        CheckRunningTournament(true)
    else
        ResetTournamentState()
    end
    if OnFisherHotspotJobChanged then
        OnFisherHotspotJobChanged(isFisher)
    end
end

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    RemoveTournamentBlips()
    CloseTournamentResults()
end)
--WKLeak_avOnpSTopfz : https://discord.gg/zqcBffbMZn
--WKLeakTOOnnDTopPL : https://discord.gg/zqcBffbMZn
--WKLeak_RMOnACTopYr : https://discord.gg/zqcBffbMZn
--WKLeak_h#On7jTopo3 : https://discord.gg/zqcBffbMZn
--WKLeak-f_OnR6TopPb : https://discord.gg/zqcBffbMZn
