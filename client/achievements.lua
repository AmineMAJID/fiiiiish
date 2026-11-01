--[[   -- https://discord.gg/zqcBffbMZn ]]
RegisterNUICallback("getAchievements", function(data, cb)
    cb("ok")
    CreateThread(function()
        local achievementsData = lib.callback.await("qs-fisher:getAchievements", 10000)
        if not achievementsData then
            achievementsData = {
                enabled = true,
                achievements = {},
                totals = {}
            }
        end
        SendNUIMessage({
            action = "achievementsReady",
            achievements = achievementsData
        })
    end)
end)

RegisterNetEvent("qs-fisher:achievementsUnlocked", function(achievementsList)
    if type(achievementsList) ~= "table" then
        return
    end
    CreateThread(function()
        for _, achievement in ipairs(achievementsList) do
            local title
            if achievement.species then
                local fmt = Lang("ACHIEVEMENT_SPECIES")
                title = fmt:format(achievement.label or achievement.species)
            else
                local key = "ACHIEVEMENT_" .. tostring(achievement.id):upper()
                title = Lang(key)
            end
            local text = Lang("ACHIEVEMENT_UNLOCKED"):format(title)
            CreateNotification("notify", "success", text)
            Wait(1600)
        end
        if #achievementsList > 0 then
            CreateNotification("notify", "info", Lang("ACHIEVEMENT_CLAIM_HINT"))
        end
    end)
end)

RegisterNUICallback("claimAchievement", function(data, cb)
    local achievementId = type(data) == "table" and data.id or nil
    cb({ ok = true })
    if type(achievementId) ~= "string" or achievementId == "" then
        return
    end
    CreateThread(function()
        local result = lib.callback.await("qs-fisher:claimAchievement", 10000, achievementId)
        if not result or not result.ok then
            local reason = (result and result.reason) or "unavailable"
            local message = Lang("ACHIEVEMENT_CLAIM_FAILED")
            if reason == "claimed" then
                message = Lang("ACHIEVEMENT_ALREADY_CLAIMED") or message
            elseif reason == "locked" then
                message = Lang("ACHIEVEMENT_NOT_EARNED") or message
            end
            return CreateNotification("notify", "error", message)
        end
        CreateNotification("notify", "success", Lang("ACHIEVEMENT_CLAIMED"))
        local updatedData = lib.callback.await("qs-fisher:getAchievements", 10000)
        if updatedData then
            SendNUIMessage({
                action = "achievementsReady",
                achievements = updatedData
            })
        end
    end)
end)
--WKLeaksS9OnxtTopE0 : https://discord.gg/zqcBffbMZn
--WKLeak9$On0UTopxp : https://discord.gg/zqcBffbMZn
--WKLeak_7oOninTop2z : https://discord.gg/zqcBffbMZn
--WKLeak-SmOnl@Toply : https://discord.gg/zqcBffbMZn
--WKLeak_QBOn#!TopcJ : https://discord.gg/zqcBffbMZn
