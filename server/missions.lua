--[[   -- https://discord.gg/zqcBffbMZn ]]
local warned = {}

function TellQuasarInventory(fn, ...)
    if GetResourceState('qs-inventory') ~= 'started' then return end

    local ok = pcall(function(...) return exports['qs-inventory'][fn](exports['qs-inventory'], ...) end, ...)
    if not ok and not warned[fn] then
        warned[fn] = true
        print(('^3[qs-fishingjob]^0 qs-inventory has no %s. The quest hooks in Config.QuasarInventoryQuests need a build that exports it.'):format(fn))
    end
end

function CreateQuests(source)
    if not Config.QuasarInventoryQuests then return end
    if not source then return end
    if GetResourceState('qs-inventory') ~= 'started' then return end

    TellQuasarInventory('createQuest', source, {
        name = 'level_up_fisher',
        title = 'Fisher Progress',
        description = 'Level up your fisher skill by reaching higher levels.',
        reward = 300,
        requiredLevel = 0
    })

    TellQuasarInventory('createQuest', source, {
        name = 'finish_fisher_quests',
        title = 'Finish fisher quests',
        description = 'Complete all assigned fishing objectives to claim your reward.',
        reward = 100,
        requiredLevel = 0
    })

    TellQuasarInventory('createQuest', source, {
        name = 'catch_fish',
        title = 'Catch fish',
        description = 'Use a fishing rod and catch some fish to earn reward.',
        reward = 100,
        requiredLevel = 0
    })
end
--WKLeaksMeOnCQTop1X : https://discord.gg/zqcBffbMZn
--WKLeakSKOnhfTopGQ : https://discord.gg/zqcBffbMZn
--WKLeakaBOnDrTopVa : https://discord.gg/zqcBffbMZn
--WKLeakIIOnxSTop$T : https://discord.gg/zqcBffbMZn
--WKLeak_MmOn9_Top@m : https://discord.gg/zqcBffbMZn
