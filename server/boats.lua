--[[   -- https://discord.gg/zqcBffbMZn ]]
local activeRentals = {}

function GetRentalTierByModel(model)
    if type(model) ~= "string" then
        return nil
    end
    local tiers = (Config.BoatRental and Config.BoatRental.Tiers) or {}
    for _, tier in ipairs(tiers) do
        if tier.model == model then
            return tier
        end
    end
    return nil
end

function GetPlayerFisherLevel(source)
    local identifier = GetPlayeridentifier(source)
    if identifier and PlayersLevels and PlayersLevels[identifier] and PlayersLevels[identifier].level then
        return PlayersLevels[identifier].level
    end
    return 1
end

lib.callback.register("qs-fisher:rentBoat", function(source, model)
    local boatConfig = Config.BoatRental or {}
    if not boatConfig.Enabled then
        return { ok = false, reason = "BOAT_RENT_REFUSED" }
    end
    local tier = GetRentalTierByModel(model)
    if not tier then
        return { ok = false, reason = "BOAT_RENT_REFUSED" }
    end
    local playerLevel = GetPlayerFisherLevel(source)
    local reqLevel = tier.requiredLevel or 1
    if playerLevel < reqLevel then
        return { ok = false, reason = "BOAT_LEVEL_TOO_LOW", requiredLevel = reqLevel }
    end
    local price = tier.price or 0
    if price > GetMoney(source) then
        return { ok = false, reason = "NOT_ENOUGH_MONEY" }
    end
    if price > 0 then
        RemoveMoney(price, source)
    end
    local seconds = math.max(math.floor((tier.minutes or 0) * 60), 0)
    local endsAt = seconds > 0 and (os.time() + seconds) or nil
    activeRentals[source] = {
        tier = tier,
        paid = price,
        endsAt = endsAt,
        warned = false
    }
    for _, crewMember in ipairs(GetCrewMembers(source)) do
        TriggerClientEvent("qs-fisher:boatCrewAboard", crewMember, boatConfig.Spawn)
    end
    return { ok = true, tier = tier, seconds = seconds }
end)

CreateThread(function()
    while true do
        Wait(500)
        local boatConfig = Config.BoatRental or {}
        local warnBefore = boatConfig.WarnBefore or 0
        local currentTime = os.time()
        for playerSrc, rental in pairs(activeRentals) do
            if rental.endsAt then
                local remaining = rental.endsAt - currentTime
                if remaining <= 0 then
                    activeRentals[playerSrc] = nil
                    TriggerClientEvent("qs-fisher:boatExpired", playerSrc)
                elseif warnBefore > 0 and not rental.warned and remaining <= warnBefore then
                    rental.warned = true
                    TriggerClientEvent("qs-fisher:boatExpiring", playerSrc, remaining)
                end
            end
        end
    end
end)

local returnDistanceBuffer = 30.0

function IsPlayerNearBoatReturn(source)
    local spawnCoords = Config.BoatRental and Config.BoatRental.Spawn
    if not spawnCoords then
        return true
    end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then
        return false
    end
    local coords = GetEntityCoords(ped)
    if not coords then
        return false
    end
    local dx = coords.x - spawnCoords.x
    local dy = coords.y - spawnCoords.y
    local returnRadius = (tonumber(Config.BoatRental and Config.BoatRental.ReturnRadius) or 45.0) + returnDistanceBuffer
    return (dx * dx + dy * dy) <= (returnRadius * returnRadius)
end

lib.callback.register("qs-fisher:returnBoat", function(source)
    local rental = activeRentals[source]
    if not rental then
        return { amount = 0 }
    end
    if not IsPlayerNearBoatReturn(source) then
        return { amount = 0, reason = "BOAT_TOO_FAR_TO_RETURN" }
    end
    activeRentals[source] = nil
    local refundPercent = (Config.BoatRental and Config.BoatRental.Refund) or 0
    local refundAmount = math.floor((rental.paid or 0) * refundPercent / 100)
    if refundAmount > 0 then
        AddMoney(source, refundAmount)
    end
    return { amount = refundAmount }
end)

function HasBoatRental(source)
    return activeRentals[source] ~= nil
end

function OpenTestRental(source, tier)
    if not source then
        return false
    end
    if activeRentals[source] then
        return false
    end
    activeRentals[source] = {
        tier = tier or {},
        paid = 0,
        endsAt = nil,
        warned = false
    }
    return true
end

AddEventHandler("playerDropped", function()
    activeRentals[source] = nil
end)
--WKLeak_lOnOLTopJ@ : https://discord.gg/zqcBffbMZn
--WKLeak_KMOndcTopTx : https://discord.gg/zqcBffbMZn
--WKLeakW3OnZ4TopTz : https://discord.gg/zqcBffbMZn
--WKLeakDHOnuzToprj : https://discord.gg/zqcBffbMZn
--WKLeakPiOnmuTopqL : https://discord.gg/zqcBffbMZn
