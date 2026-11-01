--[[   -- https://discord.gg/zqcBffbMZn ]]
local playerClothing = {
    male = {
        ["arms"] = 5,
        ["arms_2"] = 0,
        ["tshirt_1"] = 0,
        ["tshirt_2"] = 2,
        ["torso_1"] = 303,
        ["torso_2"] = 22,
        ["pants_1"] = 130,
        ["pants_2"] = 1,
        ["shoes_1"] = 110,
        ["shoes_2"] = 0,
        ["helmet_1"] = 104,
        ["helmet_2"] = 20,
        ["chain_1"] = 0,
        ["chain_2"] = 0,
        ["bags_1"] = 0,
        ["bags_2"] = 0,
        ["glasses_1"] = 0,
        ["glasses_2"] = 0
    },
    female = {
        ["arms"] = 4,
        ["arms_2"] = 0,
        ["tshirt_1"] = 71,
        ["tshirt_2"] = 2,
        ["torso_1"] = 187,
        ["torso_2"] = 0,
        ["pants_1"] = 129,
        ["pants_2"] = 0,
        ["shoes_1"] = 53,
        ["shoes_2"] = 1,
        ["helmet_1"] = 93,
        ["helmet_2"] = 5,
        ["chain_1"] = 0,
        ["chain_2"] = 0,
        ["bags_1"] = 0,
        ["bags_2"] = 0,
        ["glasses_1"] = 5,
        ["glasses_2"] = 0
    }
}

local divingClothing = {
    male = {
        ["arms"] = 17,
        ["tshirt_1"] = 15,
        ["tshirt_2"] = 0,
        ["torso_1"] = 243,
        ["torso_2"] = 0,
        ["decals_1"] = 0,
        ["decals_2"] = 0,
        ["pants_1"] = 94,
        ["pants_2"] = 0,
        ["shoes_1"] = 67,
        ["shoes_2"] = 0,
        ["helmet_1"] = 8,
        ["helmet_2"] = 0,
        ["chain_1"] = 0,
        ["chain_2"] = 0,
        ["ears_1"] = -1,
        ["ears_2"] = 0,
        ["mask_1"] = 0,
        ["mask_2"] = 0,
        ["bags_1"] = 43,
        ["bags_2"] = 0,
        ["glasses_1"] = 26,
        ["glasses_2"] = 0,
        ["bproof_1"] = 0,
        ["bproof_2"] = 0
    },
    female = {
        ["arms"] = 36,
        ["tshirt_1"] = 3,
        ["tshirt_2"] = 0,
        ["torso_1"] = 251,
        ["torso_2"] = 0,
        ["decals_1"] = 0,
        ["decals_2"] = 0,
        ["pants_1"] = 97,
        ["pants_2"] = 0,
        ["shoes_1"] = 70,
        ["shoes_2"] = 0,
        ["helmet_1"] = -1,
        ["helmet_2"] = 0,
        ["chain_1"] = 0,
        ["chain_2"] = 0,
        ["ears_1"] = -1,
        ["ears_2"] = 0,
        ["mask_1"] = 0,
        ["mask_2"] = 0,
        ["bags_1"] = 43,
        ["bags_2"] = 0,
        ["glasses_1"] = 28,
        ["glasses_2"] = 0,
        ["bproof_1"] = 0,
        ["bproof_2"] = 0
    }
}

local onDuty = false
local diving = false
local worn = nil
local activeOutfit = playerClothing

function WantedOutfit()
    if diving then return divingClothing end
    if onDuty then return playerClothing end
    return nil
end

function ApplyOutfit()
    local want = WantedOutfit()
    if want == worn then return end
    worn = want

    if not Config.Clothing then return end

    activeOutfit = want or playerClothing
    local enable = want ~= nil

    if Config.QuasarInventory then
        pcall(function() exports['qs-inventory']:setInClothing(true) end)
    end

    if Config.Framework == "esx" then
        if not enable then
            ESX.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin)
                TriggerEvent('skinchanger:loadSkin', skin)
            end)
        else
            ESX.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin)
                local outfit = (skin.sex == 0) and activeOutfit.male or activeOutfit.female
                TriggerEvent('skinchanger:loadClothes', skin, {
                    ['arms'] = outfit["arms"],
                    ['tshirt_1'] = outfit["tshirt_1"],
                    ['tshirt_2'] = outfit["tshirt_2"],
                    ['torso_1'] = outfit["torso_1"],
                    ['torso_2'] = outfit["torso_2"],
                    ['decals_1'] = outfit["decals_1"],
                    ['decals_2'] = outfit["decals_2"],
                    ['pants_1'] = outfit["pants_1"],
                    ['pants_2'] = outfit["pants_2"],
                    ['shoes_1'] = outfit["shoes_1"],
                    ['shoes_2'] = outfit["shoes_2"],
                    ['helmet_1'] = outfit["helmet_1"],
                    ['helmet_2'] = outfit["helmet_2"],
                    ['chain_1'] = outfit["chain_1"],
                    ['chain_2'] = outfit["chain_2"],
                    ['ears_1'] = outfit["ears_1"],
                    ['ears_2'] = outfit["ears_2"],
                    ['mask_1'] = outfit["mask_1"],
                    ['mask_2'] = outfit["mask_2"],
                    ['bags_1'] = outfit["bags_1"],
                    ['bags_2'] = outfit["bags_2"],
                    ['glasses_1'] = outfit["glasses_1"],
                    ['glasses_2'] = outfit["glasses_2"],
                    ['bproof_1'] = outfit["vest_1"],
                    ['bproof_2'] = outfit["vest_2"],
                    ['watches_1'] = outfit["watches_1"],
                    ['watches_2'] = outfit["watches_2"],
                    ['bracelets_1'] = outfit["bracelets_1"],
                    ['bracelets_2'] = outfit["bracelets_2"]
                })
            end)
        end
    elseif Config.Framework == "qb" then
        if not enable then
            TriggerServerEvent("qb-clothes:loadPlayerSkin")
        else
            local gender = PlayerData and PlayerData.charinfo and PlayerData.charinfo.gender or 0
            local outfit = (gender == 0) and activeOutfit.male or activeOutfit.female
            TriggerEvent("qb-clothing:client:loadOutfit", {
                ["outfitData"] = {
                    ["arms"]      = { item = outfit["arms"], texture = 0 },
                    ["t-shirt"]   = { item = outfit["tshirt_1"], texture = outfit["tshirt_2"] },
                    ["torso2"]    = { item = outfit["torso_1"], texture = outfit["torso_2"] },
                    ["decals"]    = { item = outfit["decals_1"], texture = outfit["decals_2"] },
                    ["pants"]     = { item = outfit["pants_1"], texture = outfit["pants_2"] },
                    ["shoes"]     = { item = outfit["shoes_1"], texture = outfit["shoes_2"] },
                    ["hat"]       = { item = outfit["helmet_1"], texture = outfit["helmet_2"] },
                    ["accessory"] = { item = outfit["chain_1"], texture = outfit["chain_2"] },
                    ["ear"]       = { item = outfit["ears_1"], texture = outfit["ears_2"] },
                    ["mask"]      = { item = outfit["mask_1"], texture = outfit["mask_2"] },
                    ["bag"]       = { item = outfit["bags_1"], texture = outfit["bags_2"] },
                    ["glass"]     = { item = outfit["glasses_1"], texture = outfit["glasses_2"] },
                    ["vest"]      = { item = outfit["vest_1"], texture = outfit["vest_2"] },
                    ["watch"]     = { item = outfit["watches_1"], texture = outfit["watches_2"] },
                    ["bracelet"]  = { item = outfit["bracelets_1"], texture = outfit["bracelets_2"] }
                }
            })
        end
    end

    if Config.QuasarInventory then
        pcall(function() exports['qs-inventory']:setInClothing(false) end)
    end
end

function ToggleDiveClothes(enable)
    diving = enable and true or false
    ApplyOutfit()
end

function ToggleJobClothes(enable)
    enable = enable and true or false
    if enable == onDuty then return end
    onDuty = enable
    TriggerServerEvent('qs-fisher:setDutyStatus', enable)
    ApplyOutfit()
end
--WKLeakvPOnpaTopeB : https://discord.gg/zqcBffbMZn
--WKLeaksnROnTRTopn@ : https://discord.gg/zqcBffbMZn
--WKLeaku3OnbMTop90 : https://discord.gg/zqcBffbMZn
--WKLeak-m1OnuaTopg6 : https://discord.gg/zqcBffbMZn
--WKLeakl1OnRCTopZ- : https://discord.gg/zqcBffbMZn
