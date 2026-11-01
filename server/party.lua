--[[   -- https://discord.gg/zqcBffbMZn ]]
local parties = {}
local playerToPartyLeader = {}
local pendingInvites = {}
local activeGroupQuests = {}
local INVITE_TIMEOUT_MS = 60000

function GetPartyForPlayer(src)
    local leaderId = playerToPartyLeader[src]
    if leaderId then
        return parties[leaderId]
    end
    return nil
end

function GetOrCreateParty(src)
    local existing = GetPartyForPlayer(src)
    if existing then
        return existing
    end

    local newParty = {
        leader = src,
        maxMembers = Config.MaxPartyMembers,
        members = {
            {
                id = src,
                name = ResolvePlayerName(src),
                isLeader = true
            }
        }
    }
    parties[src] = newParty
    playerToPartyLeader[src] = src
    return newParty
end

function CreateDefaultPartyView(src)
    return {
        leader = src,
        maxMembers = Config.MaxPartyMembers,
        members = {
            {
                id = src,
                name = ResolvePlayerName(src),
                isLeader = true
            }
        }
    }
end

function IsPlayerInParty(src)
    return GetPartyForPlayer(src) ~= nil
end

function GetCrewMembers(src)
    local party = GetPartyForPlayer(src)
    if not party then
        return {}
    end
    local crew = {}
    for _, member in ipairs(party.members) do
        if member.id ~= src then
            crew[#crew + 1] = member.id
        end
    end
    return crew
end

function BroadcastPartyUpdate(party)
    for _, member in ipairs(party.members) do
        TriggerClientEvent("qs-fisher:partyUpdated", member.id, party)
    end
end

function RemovePlayerFromParty(src)
    local leaderId = playerToPartyLeader[src]
    if not leaderId then
        return
    end

    local party = parties[leaderId]
    playerToPartyLeader[src] = nil
    if not party then
        return
    end

    if leaderId == src then
        for _, member in ipairs(party.members) do
            playerToPartyLeader[member.id] = nil
            if member.id ~= src then
                TriggerClientEvent("qs-fisher:partyUpdated", member.id, nil)
            end
        end
        parties[leaderId] = nil
        return
    end

    for i = #party.members, 1, -1 do
        if party.members[i].id == src then
            table.remove(party.members, i)
            break
        end
    end

    if #party.members <= 1 then
        for _, member in ipairs(party.members) do
            playerToPartyLeader[member.id] = nil
        end
        parties[leaderId] = nil
    else
        BroadcastPartyUpdate(party)
    end
end

lib.callback.register("qs-fisher:getParty", function(src)
    return GetPartyForPlayer(src) or CreateDefaultPartyView(src)
end)

RegisterNetEvent("qs-fisher:invitePlayerToParty", function(targetPlayerId)
    local src = source
    local targetId = tonumber(targetPlayerId)
    if not targetId or targetId == src then
        return
    end

    if not GetPlayerName(targetId) then
        return TriggerClientEvent("qs-fisher:sendNotification", src, "notify", "error", Lang("PLAYER_NOT_FOUND"))
    end

    local party = GetOrCreateParty(src)
    if party.leader ~= src then
        return TriggerClientEvent("qs-fisher:sendNotification", src, "notify", "error", Lang("NOT_PARTY_LEADER"))
    end

    if #party.members >= Config.MaxPartyMembers then
        return TriggerClientEvent("qs-fisher:sendNotification", src, "notify", "error", Lang("MAX_MEMBERS_IN_PARTY"))
    end

    if IsPlayerInParty(targetId) then
        return TriggerClientEvent("qs-fisher:sendNotification", src, "notify", "error", Lang("PLAYER_ALREADY_IN_PARTY"))
    end

    pendingInvites[targetId] = {
        inviterId = src,
        expires = GetGameTimer() + INVITE_TIMEOUT_MS
    }

    local maxDistance = Config.InviteDistance or 0
    if maxDistance > 0 then
        local srcPed = GetPlayerPed(src)
        local targetPed = GetPlayerPed(targetId)
        if srcPed ~= 0 and targetPed ~= 0 then
            local dist = #(GetEntityCoords(srcPed) - GetEntityCoords(targetPed))
            if dist > maxDistance then
                return TriggerClientEvent("qs-fisher:sendNotification", src, "notify", "error", Lang("NOTIFY_PLAYER_TOO_FAR"))
            end
        end
    end

    TriggerClientEvent("qs-fisher:receivePartyInvitation", targetId, {
        inviterName = ResolvePlayerName(src),
        inviterId = src
    })
end)

RegisterNetEvent("qs-fisher:declinePartyInvitation", function()
    pendingInvites[source] = nil
end)

RegisterNetEvent("qs-fisher:acceptPartyInvitation", function(inviterId)
    local src = source
    local invite = pendingInvites[src]
    pendingInvites[src] = nil
    if not invite then
        return
    end

    if inviterId and tonumber(inviterId) ~= invite.inviterId then
        return
    end

    if GetGameTimer() > invite.expires then
        return
    end

    local party = parties[invite.inviterId]
    if not party or party.leader ~= invite.inviterId then
        return
    end

    if #party.members >= Config.MaxPartyMembers then
        return TriggerClientEvent("qs-fisher:sendNotification", src, "notify", "error", Lang("MAX_MEMBERS_IN_PARTY"))
    end

    if IsPlayerInParty(src) then
        return TriggerClientEvent("qs-fisher:sendNotification", src, "notify", "error", Lang("ALREADY_IN_A_PARTY"))
    end

    if playerToPartyLeader[src] then
        RemovePlayerFromParty(src)
    end

    local playerName = ResolvePlayerName(src)
    party.members[#party.members + 1] = {
        id = src,
        name = playerName,
        isLeader = false
    }
    playerToPartyLeader[src] = party.leader

    TriggerClientEvent("qs-fisher:playerAcceptedInvitation", party.leader, {
        id = src,
        name = playerName
    })
    BroadcastPartyUpdate(party)
end)

RegisterNetEvent("qs-fisher:kickFromParty", function(targetPlayerId)
    local src = source
    local targetId = tonumber(targetPlayerId)
    if not targetId then
        return
    end

    local party = GetPartyForPlayer(src)
    if not party or party.leader ~= src or targetId == src then
        return
    end

    if playerToPartyLeader[targetId] ~= party.leader then
        return
    end

    RemovePlayerFromParty(targetId)
    TriggerClientEvent("qs-fisher:partyUpdated", targetId, nil)
end)

function GetTaskByOrder(taskOrder)
    for _, task in ipairs(Config.Tasks or {}) do
        if task.taskOrder == taskOrder then
            return task
        end
    end
    return nil
end

RegisterNetEvent("qs-fisher:startGroupQuest", function(taskOrder)
    local src = source
    local orderNum = tonumber(taskOrder)
    local task = orderNum and GetTaskByOrder(orderNum)
    if not task then
        return
    end

    local party = GetOrCreateParty(src)
    if party.leader ~= src then
        return TriggerClientEvent("qs-fisher:startGroupQuestFailed", src, "NOT_PARTY_LEADER")
    end

    for _, member in ipairs(party.members) do
        local identifier = GetPlayeridentifier(member.id)
        local memberLevel = identifier and PlayersLevels and PlayersLevels[identifier] and PlayersLevels[identifier].level
        local reqLevel = task.levelRequired or 1
        if memberLevel and memberLevel < reqLevel then
            return TriggerClientEvent("qs-fisher:startGroupQuestFailed", src, "NOT_ENOUGH_LEVEL_MEMBERS")
        end
    end

    local questData = {}
    for index, fishKey in ipairs(task.fishRequired or {}) do
        local requiredAmount = (task.fishAmount and task.fishAmount[index]) or 1
        questData[#questData + 1] = {
            fish = Lang(fishKey:upper()),
            key = fishKey,
            maxAmount = requiredAmount,
            amount = 0
        }
    end

    local groupId = ("%d-%d"):format(src, GetGameTimer())
    local membersCopy = {}
    for _, member in ipairs(party.members) do
        membersCopy[#membersCopy + 1] = {
            id = member.id,
            name = member.name
        }
    end

    activeGroupQuests[groupId] = {
        members = membersCopy,
        taskOrder = orderNum,
        questData = questData
    }

    for _, member in ipairs(membersCopy) do
        TriggerClientEvent("qs-fisher:openGroupQuestUI", member.id, {
            taskOrder = orderNum,
            questData = questData,
            groupId = groupId
        })
    end

    if task.hunt and StartSharkHunt then
        local hunterIds = {}
        for _, member in ipairs(membersCopy) do
            hunterIds[#hunterIds + 1] = member.id
        end
        StartSharkHunt(hunterIds)
    end

    if SendWebhook then
        local askedList = {}
        for _, q in ipairs(questData) do
            askedList[#askedList + 1] = ("%s x%d"):format(q.fish, q.maxAmount)
        end
        local crewNames = {}
        for _, m in ipairs(membersCopy) do
            crewNames[#crewNames + 1] = m.name
        end
        local taskTitle = task.name or ("Task " .. orderNum)
        local fields = {
            WebhookField("Asked for", table.concat(askedList, ", "), false),
            WebhookField("Crew", table.concat(crewNames, ", "), false),
            WebhookField("Pays", task.money and ("$" .. task.money) or nil),
            WebhookField("Experience", task.experience)
        }
        SendWebhook("MissionStarted", src, "Mission started", taskTitle, fields)
    end
end)

function UpdateGroupQuestProgress(src, fishKey, amount)
    for groupId, groupQuest in pairs(activeGroupQuests) do
        local isMember = false
        for _, member in ipairs(groupQuest.members) do
            if member.id == src then
                isMember = true
                break
            end
        end

        if isMember then
            local targetObjective = nil
            for _, obj in ipairs(groupQuest.questData) do
                if obj.key == fishKey then
                    targetObjective = obj
                    break
                end
            end
            if not targetObjective then
                return
            end

            targetObjective.amount = math.min(targetObjective.amount + amount, targetObjective.maxAmount)
            for _, member in ipairs(groupQuest.members) do
                TriggerClientEvent("qs-fisher:updateGroupQuestProgressUI", member.id, groupQuest.questData)
            end

            local isAllComplete = true
            for _, obj in ipairs(groupQuest.questData) do
                if obj.amount < obj.maxAmount then
                    isAllComplete = false
                    break
                end
            end

            if isAllComplete then
                local task = GetTaskByOrder(groupQuest.taskOrder)
                if SendWebhook then
                    local crewNames = {}
                    for _, m in ipairs(groupQuest.members) do
                        crewNames[#crewNames + 1] = m.name
                    end
                    local splitCount = 1
                    if Config.MissionPayout == "split" then
                        splitCount = math.max(#groupQuest.members, 1)
                    end

                    function CalculateSplit(val)
                        local num = math.floor(tonumber(val) or 0)
                        if num <= 0 or splitCount <= 1 then
                            return num
                        end
                        return math.max(math.floor(num / splitCount), 1)
                    end

                    local baseMoney = task and task.money or 0
                    local baseExp = task and task.experience or 0
                    local taskTitle = (task and task.name) or ("Task " .. tostring(groupQuest.taskOrder))

                    local paysText = (splitCount > 1) and ("$%d each (pot $%d)"):format(CalculateSplit(baseMoney), baseMoney) or ("$" .. baseMoney)
                    local expText = (splitCount > 1) and ("%d each (pot %d)"):format(CalculateSplit(baseExp), baseExp) or baseExp

                    local fields = {
                        WebhookField("Crew", table.concat(crewNames, ", "), false),
                        WebhookField("Pays", paysText),
                        WebhookField("Experience", expText)
                    }
                    SendWebhook("MissionFinished", src, "Mission finished", taskTitle, fields)
                end

                local payoutDivisor = 1
                if Config.MissionPayout == "split" then
                    payoutDivisor = math.max(#groupQuest.members, 1)
                end

                for _, member in ipairs(groupQuest.members) do
                    TriggerClientEvent("qs-fisher:completeGroupQuest", member.id)
                    if task and PayForMission then
                        PayForMission(member.id, task, payoutDivisor)
                    end
                    if task and task.hunt and StopSharkHunt then
                        StopSharkHunt(member.id)
                    end
                end
                activeGroupQuests[groupId] = nil
            end
            return
        end
    end
end

function IsPlayerOnMission(playerId)
    local targetId = tonumber(playerId)
    if not targetId then
        return false
    end
    for _, groupQuest in pairs(activeGroupQuests) do
        for _, member in ipairs(groupQuest.members) do
            if member.id == targetId then
                return true
            end
        end
    end
    return false
end

exports("IsPlayerOnMission", IsPlayerOnMission)

RegisterNetEvent("qs-fisher:leaveGroup", function()
    local src = source
    for groupId, groupQuest in pairs(activeGroupQuests) do
        for i = #groupQuest.members, 1, -1 do
            if groupQuest.members[i].id == src then
                if SendWebhook then
                    local task = GetTaskByOrder(groupQuest.taskOrder)
                    local taskTitle = (task and task.name) or ("Task " .. tostring(groupQuest.taskOrder))
                    local remainingCount = #groupQuest.members - 1
                    local totalCount = #groupQuest.members
                    local fields = {
                        WebhookField("Left behind", ("%d of %d still in the crew"):format(remainingCount, totalCount), false)
                    }
                    SendWebhook("MissionAbandoned", src, "Mission abandoned", taskTitle, fields)
                end
                table.remove(groupQuest.members, i)
                if #groupQuest.members == 0 then
                    activeGroupQuests[groupId] = nil
                end
                break
            end
        end
    end

    if StopSharkHunt then
        StopSharkHunt(src)
    end
    RemovePlayerFromParty(src)
end)

AddEventHandler("playerDropped", function()
    local src = source
    pendingInvites[src] = nil

    for groupId, groupQuest in pairs(activeGroupQuests) do
        for i = #groupQuest.members, 1, -1 do
            if groupQuest.members[i].id == src then
                if SendWebhook then
                    local task = GetTaskByOrder(groupQuest.taskOrder)
                    local taskTitle = (task and task.name) or ("Task " .. tostring(groupQuest.taskOrder))
                    local fields = {
                        WebhookField("Reason", "Disconnected", false)
                    }
                    SendWebhook("MissionAbandoned", src, "Mission abandoned", taskTitle, fields)
                end
                table.remove(groupQuest.members, i)
                if #groupQuest.members == 0 then
                    activeGroupQuests[groupId] = nil
                    break
                end
                for _, member in ipairs(groupQuest.members) do
                    TriggerClientEvent("qs-fisher:updateGroupQuestProgressUI", member.id, groupQuest.questData)
                end
                break
            end
        end
    end

    for targetId, invite in pairs(pendingInvites) do
        if invite.inviterId == src then
            pendingInvites[targetId] = nil
        end
    end

    RemovePlayerFromParty(src)
end)
--WKLeak_a$OnKITopjs : https://discord.gg/zqcBffbMZn
--WKLeakTEOnEyTopcX : https://discord.gg/zqcBffbMZn
--WKLeak-kWOnl9TopLc : https://discord.gg/zqcBffbMZn
--WKLeak_DFOnuhTopGB : https://discord.gg/zqcBffbMZn
--WKLeak-5vOnUnTopkg : https://discord.gg/zqcBffbMZn
