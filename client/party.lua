--[[   -- https://discord.gg/zqcBffbMZn ]]
local activeHeadshots = {}
local registerHeadshotFn = RegisterPedheadshot

local highResCandidates = {
    "RegisterPedheadshotHires",
    "RegisterPedheadshotHiRes",
    "RegisterPedheadshotHighRes"
}
for _, fnName in ipairs(highResCandidates) do
    local fn = rawget(_G, fnName)
    if type(fn) == "function" then
        registerHeadshotFn = fn
        break
    end
end

local transparentHeadshotFn = rawget(_G, "RegisterPedheadshotTransparent")
if type(transparentHeadshotFn) ~= "function" then
    transparentHeadshotFn = nil
end

function UnregisterAllPedheadshots()
    for _, handle in ipairs(activeHeadshots) do
        UnregisterPedheadshot(handle)
    end
    activeHeadshots = {}
end

function GetPedMugshot(serverId)
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then
        return nil, "player is not in scope"
    end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return nil, "their ped is not streamed in"
    end

    local originalLod = GetEntityLodDist(ped)
    SetEntityLodDist(ped, 1000)

    local handle = 0
    local isCutout = false
    if transparentHeadshotFn then
        handle = transparentHeadshotFn(ped)
        isCutout = (handle ~= 0)
    end
    if handle == 0 then
        handle = registerHeadshotFn(ped)
    end
    if handle == 0 then
        SetEntityLodDist(ped, originalLod)
        return nil, "no free headshot slot"
    end

    local timeout = GetGameTimer() + 3000
    while true do
        if IsPedheadshotReady(handle) and IsPedheadshotValid(handle) then
            break
        end
        if GetGameTimer() > timeout then
            UnregisterPedheadshot(handle)
            SetEntityLodDist(ped, originalLod)
            return nil, "the headshot render timed out"
        end
        Wait(0)
    end

    SetEntityLodDist(ped, originalLod)
    activeHeadshots[#activeHeadshots + 1] = handle
    local txd = GetPedheadshotTxdString(handle)
    return ("https://nui-img/%s/%s"):format(txd, txd), nil, isCutout
end

function LoadPartyMugshots(members)
    UnregisterAllPedheadshots()
    for _, member in ipairs(members or {}) do
        local mugshotUrl, err, isCutout = GetPedMugshot(member.id)
        member.mugshot = mugshotUrl
        member.mugshotCutout = isCutout
    end
end

function GetFishLabel(fishName)
    local str = tostring(fishName):upper()
    local trans = Lang(str)
    if trans and trans ~= str then
        return trans
    end
    local fishDef = Config.Fish and Config.Fish[fishName]
    local items = fishDef and fishDef.items
    if items and items[1] and items[1][2] then
        return items[1][2]
    end
    local clean = tostring(fishName):gsub("_", " ")
    return clean:gsub("^%l", string.upper)
end

function GetPartyTasks()
    local taskList = {}
    local rawTasks = Config.Tasks or {}
    for _, task in ipairs(rawTasks) do
        local objectives = {}
        local required = task.fishRequired or {}
        local amounts = task.fishAmount or {}
        for index, fishItem in ipairs(required) do
            objectives[#objectives + 1] = {
                item = fishItem,
                label = GetFishLabel(fishItem),
                amount = amounts[index] or 1
            }
        end
        local taskEntry = {}
        for k, v in pairs(task) do
            taskEntry[k] = v
        end
        taskEntry.objectives = objectives
        taskEntry.kind = task.hunt and "hunt" or "catch"
        taskList[#taskList + 1] = taskEntry
    end
    return taskList
end

function UpdatePartyMemberMugshotThread(serverId, name)
    CreateThread(function()
        local lastError = nil
        for attempt = 1, 4 do
            local mugshotUrl, err, isCutout = GetPedMugshot(serverId)
            lastError = err
            if mugshotUrl then
                SendNUIMessage({
                    action = "updatePartyMembers",
                    data = {
                        id = serverId,
                        name = name,
                        isLeader = false,
                        mugshot = mugshotUrl,
                        mugshotCutout = isCutout
                    }
                })
                return
            end
            Wait(500)
        end
        print(("^3[qs-fishingjob] ^7no mugshot for %s (id %s): %s."):format(tostring(name), tostring(serverId), lastError or "unknown"))
    end)
end

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    UnregisterAllPedheadshots()
end)

function ClosePartyUI()
    UnregisterAllPedheadshots()
    SetNuiFocus(false, false)
    StopPedDialogueCam()
end

function OpenPartyMenu()
    DebugPrint("opening the job panel")
    local serverId = GetPlayerServerId(PlayerId())
    local level, exp, expRequired = GetPlayerLevel()
    local bonuses = GetLevelBonuses(level)

    local partyData = lib.callback.await("qs-fisher:getParty", false)
    if not partyData then
        partyData = {
            maxMembers = Config.MaxPartyMembers,
            members = {
                {
                    id = serverId,
                    name = GetDisplayName(),
                    isLeader = true
                }
            }
        }
    end
    Party = partyData
    LoadPartyMugshots(partyData.members)

    SendNUIMessage({
        action = "openPartyUI",
        party = partyData,
        id = serverId,
        tasks = GetPartyTasks(),
        leaderboard = Config.EnableLeaderboard,
        guide = Config.WaterGuide and Config.WaterGuide.Enabled,
        achievements = (Config.Achievements and Config.Achievements.Enabled) ~= false,
        onDuty = (Player.onDuty == true),
        activeTask = Player.type,
        pedName = Config.PedName or "",
        pedGreeting = Config.PedGreeting or "",
        playerLevelInfo = {
            level = level,
            experience = exp,
            experienceRequired = expRequired,
            fightEaseBonus = bonuses.fightEase,
            extraCatchChanceBonus = bonuses.extraCatchChance,
            biteTimeReductionBonus = bonuses.biteTimeReduction
        }
    })

    SetNuiFocus(true, true)
    StartPedDialogueCam()
end

RegisterNUICallback("closePartyList", function(data, cb)
    ClosePartyUI()
    cb("ok")
end)

RegisterNUICallback("invitePlayerToParty", function(data, cb)
    local targetId = tonumber(data.playerId)
    if targetId then
        TriggerServerEvent("qs-fisher:invitePlayerToParty", targetId)
    end
    cb({})
end)

RegisterNetEvent("qs-fisher:receivePartyInvitation", function(inviteData)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "receivePartyInvitation",
        data = inviteData
    })
end)

RegisterNUICallback("declinePartyInvitation", function(data, cb)
    ClosePartyUI()
    TriggerServerEvent("qs-fisher:declinePartyInvitation")
    cb({})
end)

RegisterNUICallback("acceptPartyInvitation", function(data, cb)
    ClosePartyUI()
    if CanInteract then
        local inviterId = data.inviteData and tonumber(data.inviteData.inviterId)
        TriggerServerEvent("qs-fisher:acceptPartyInvitation", inviterId)
    else
        CreateNotification("notify", "error", Lang("NOTIFY_NOT_FISHER"))
    end
    cb({})
end)

RegisterNUICallback("kickPlayer", function(data, cb)
    local targetId = tonumber(data.playerId)
    if targetId then
        TriggerServerEvent("qs-fisher:kickFromParty", targetId)
    end
    cb({ success = true })
end)

RegisterNetEvent("qs-fisher:playerAcceptedInvitation", function(member)
    if not member then
        return
    end
    SendNUIMessage({
        action = "updatePartyMembers",
        data = {
            id = member.id,
            name = member.name,
            isLeader = false
        }
    })
    UpdatePartyMemberMugshotThread(member.id, member.name)
end)

RegisterNetEvent("qs-fisher:partyUpdated", function(updatedParty)
    Party = updatedParty
end)

RegisterNUICallback("startFisherTask", function(data, cb)
    if not CanInteract then
        cb({ ok = false })
        return CreateNotification("notify", "error", Lang("NOTIFY_NOT_FISHER"))
    end
    if Player.onDuty then
        cb({ ok = false })
        return CreateNotification("notify", "error", Lang("NOTIFY_ALREADY_ON_MISSION"))
    end

    cb({ ok = true })
    ClosePartyUI()
    TriggerServerEvent("qs-fisher:startGroupQuest", tonumber(data.taskOrder))
end)

RegisterNetEvent("qs-fisher:startGroupQuestFailed", function(reason)
    CreateNotification("notify", "error", Lang(reason or "NOT_ENOUGH_LEVEL_MEMBERS"))
end)

RegisterNetEvent("qs-fisher:openGroupQuestUI", function(data)
    if not data then
        return
    end
    Player.onDuty = true
    Player.type = data.taskOrder
    Player.groupId = data.groupId
    ToggleJobClothes(true)

    local currentTask = nil
    for _, task in ipairs(Config.Tasks or {}) do
        if task.taskOrder == data.taskOrder then
            currentTask = task
            break
        end
    end
    if not currentTask then
        return
    end

    SendNUIMessage({
        type = "groupQuestMenu",
        questName = currentTask.name,
        questData = data.questData,
        questDescription = currentTask.description,
        payment = currentTask.money,
        experience = currentTask.experience
    })
    CreateNotification("notify", "info", Lang("CATCH_REQUIRED_FISH"))
end)

RegisterNetEvent("qs-fisher:updateGroupQuestProgressUI", function(progressData)
    SendNUIMessage({
        type = "updateGroupQuestProgress",
        questData = progressData
    })
end)

RegisterNetEvent("qs-fisher:completeGroupQuest", function()
    ToggleJobClothes(false)
    Player.onDuty = false
    Player.type = nil
    Player.groupId = nil
    Party = nil
    SendNUIMessage({
        type = "closeMenu",
        questCompleted = Lang("MISSION_COMPLETED")
    })
end)

function AbandonMission()
    if not Player.onDuty then
        return false
    end
    TriggerServerEvent("qs-fisher:leaveGroup")
    ToggleJobClothes(false)
    Player.onDuty = false
    Player.type = nil
    Player.groupId = nil
    Party = nil
    SendNUIMessage({
        type = "closeMenu"
    })
    return true
end

RegisterNUICallback("abandonQuest", function(data, cb)
    cb({ ok = AbandonMission() })
end)

function GetDisplayName()
    local name = lib.callback.await(GetCurrentResourceName() .. ":getPlayerDisplayName", false)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return GetPlayerName(PlayerId())
end
--WKLeak-SIOnEBTopzm : https://discord.gg/zqcBffbMZn
--WKLeaksSzOn3zTopRW : https://discord.gg/zqcBffbMZn
--WKLeaksr!OnZ_TopYY : https://discord.gg/zqcBffbMZn
--WKLeak_EgOnf6Topnw : https://discord.gg/zqcBffbMZn
--WKLeak_CnOnQ4TopaQ : https://discord.gg/zqcBffbMZn
