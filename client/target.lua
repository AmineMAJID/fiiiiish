--[[   -- https://discord.gg/zqcBffbMZn ]]
function InteractWithPedJob(pedData)
    if not pedData then return end

    if Config.TargetScript == "ox" then
        exports.ox_target:addLocalEntity(pedData, {
            {
                name = "qs-fisher:startworking",
                label = Lang("TARGET_START_WORKING"),
                icon = "fa-solid fa-fish-fins",
                distance = 3,
                onSelect = function()
                    OpenPartyMenu()
                end
            }
        })
    elseif Config.TargetScript == "qb" then
        exports['qb-target']:AddTargetEntity(pedData, {
            options = {
                {
                    num = 1,
                    label = Lang("TARGET_START_WORKING"),
                    icon = "fa-solid fa-fish-fins",
                    action = function()
                        OpenPartyMenu()
                    end
                }
            },
            distance = 3
        })
    end
end
--WKLeaks0iOni1Topbc : https://discord.gg/zqcBffbMZn
--WKLeak-d0On@zTop_K : https://discord.gg/zqcBffbMZn
--WKLeak-EOOnptTopjW : https://discord.gg/zqcBffbMZn
--WKLeakjPOnSGTophQ : https://discord.gg/zqcBffbMZn
--WKLeak-MBOn0MTopsO : https://discord.gg/zqcBffbMZn
