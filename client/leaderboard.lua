--[[   -- https://discord.gg/zqcBffbMZn ]]
function ProcessLeaderboardEntries(entries, playerIdentifier)
    local list = entries or {}
    for _, entry in ipairs(list) do
        entry.isSource = (entry.identifier == playerIdentifier)
        entry.identifier = nil
    end
    return list
end

function SortLeaderboardRewards(rewards)
    table.sort(rewards, function(a, b)
        return a.reward_amount > b.reward_amount
    end)
end

function ToggleLeaderBoard()
    if not Config.EnableLeaderboard then
        return
    end
    local dailyHours, dailyMinutes = lib.callback.await("qs-fisher:getDailyTimeRemaining")
    local seasonDays, seasonHours, seasonMinutes = lib.callback.await("qs-fisher:getTimeRemainingUntilNextMonth")
    local leaderboardInfo, winnersData = lib.callback.await("qs-fisher:getLeaderboardInfo", false)
    local playerIdentifier = lib.callback.await("qs-fisher:getPlayerIdentifier")

    if not leaderboardInfo then
        leaderboardInfo = {}
    end

    local categorizedWinners = {
        daily = {},
        season = {}
    }

    for _, winner in ipairs(winnersData or {}) do
        if winner.reward_type == "daily" then
            categorizedWinners.daily[#categorizedWinners.daily + 1] = winner
        elseif winner.reward_type == "Season" then
            categorizedWinners.season[#categorizedWinners.season + 1] = winner
        end
    end

    SortLeaderboardRewards(categorizedWinners.daily)
    SortLeaderboardRewards(categorizedWinners.season)

    SendNUIMessage({
        action = "open",
        allTimeFisher = ProcessLeaderboardEntries(leaderboardInfo.allTime, playerIdentifier),
        topFishersSeason = ProcessLeaderboardEntries(leaderboardInfo.season, playerIdentifier),
        topFishersDay = ProcessLeaderboardEntries(leaderboardInfo.daily, playerIdentifier),
        heaviestFish = ProcessLeaderboardEntries(leaderboardInfo.heaviest, playerIdentifier),
        title1 = Lang("ALL_TIME_FISHER"),
        title2 = Lang("TOP_FISHER_SEASON"),
        title3 = Lang("TOP_FISHER_DAILY"),
        title4 = Lang("HEAVIEST_FISH"),
        title5 = Lang("TOURNAMENT_WINS"),
        tournamentWins = ProcessLeaderboardEntries(leaderboardInfo.tournamentWins or {}, playerIdentifier),
        weightTitle = Lang("WEIGHT"),
        qualityTitle = Lang("QUALITY"),
        winsTitle = Lang("TOURNAMENT_WINS"),
        placeTitle = Lang("PLACE"),
        usernameTitle = Lang("PLAYER_NAME"),
        experienceTitle = Lang("EXPERIENCE"),
        earningsTitle = Lang("EARNINGS"),
        dailyTimeRemainingHours = dailyHours,
        dailyTimeRemainingMinutes = dailyMinutes,
        seasonTimeRemainingDays = seasonDays,
        seasonTimeRemainingHours = seasonHours,
        seasonTimeRemainingMinutes = seasonMinutes,
        leaderBoardRewards = Config.LeaderBoardRewards,
        leaderBoardWinners = categorizedWinners
    })
end

RegisterNUICallback("requestLeaderboard", function(data, cb)
    cb({ enabled = Config.EnableLeaderboard })
    ToggleLeaderBoard()
end)

exports("openFisherMenu", function()
    OpenPartyMenu()
end)

RegisterNetEvent("qs-fisher:openFisherMenu", function()
    OpenPartyMenu()
end)
--WKLeak_uNOnlMTopCE : https://discord.gg/zqcBffbMZn
--WKLeakEAOn9CTopTR : https://discord.gg/zqcBffbMZn
--WKLeakrOOnyETopRg : https://discord.gg/zqcBffbMZn
--WKLeak_6VOnt_Topde : https://discord.gg/zqcBffbMZn
--WKLeak_IXOnA1TopF# : https://discord.gg/zqcBffbMZn
