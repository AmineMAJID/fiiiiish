--[[   -- https://discord.gg/zqcBffbMZn ]]
if Config.Vehiclekeys ~= 'glfp10_carkeys' then
    return
end

function AddVehiclekeys(vehicle, plate, item)
    if not item then return end
    if type(vehicle) ~= 'string' then return end

    local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    TriggerServerEvent('carkeys:server:buyKey', plate, model)
end

function RemoveVehiclekeys(vehicle, plate)
    return
end
--WKLeaks3qOn3hTop6q : https://discord.gg/zqcBffbMZn
--WKLeakTkOn-3Topjg : https://discord.gg/zqcBffbMZn
--WKLeak-AjOnYkTopNf : https://discord.gg/zqcBffbMZn
--WKLeak_i2OnDITopnH : https://discord.gg/zqcBffbMZn
--WKLeakWuOnI7Top_X : https://discord.gg/zqcBffbMZn
