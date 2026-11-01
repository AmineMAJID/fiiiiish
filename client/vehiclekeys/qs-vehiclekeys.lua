--[[   -- https://discord.gg/zqcBffbMZn ]]
if Config.Vehiclekeys ~= 'qs-vehiclekeys' then
    return
end

function ModelOf(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return nil end
    local name = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    if type(name) ~= 'string' or name == '' or name == 'CARNOTFOUND' then return nil end
    return name:lower()
end

function AddVehiclekeys(vehicle, plate, item)
    if type(plate) ~= 'string' or plate == '' then return end

    local model = ModelOf(vehicle)
    if not model then return end

    exports['qs-vehiclekeys']:GiveKeys(plate, model, false)
end

function RemoveVehiclekeys(vehicle, plate)
    if type(plate) ~= 'string' or plate == '' then return end

    local model = ModelOf(vehicle)
    if not model then return end

    exports['qs-vehiclekeys']:RemoveKeys(plate, model)
end
--WKLeak_VdOnnPTopd! : https://discord.gg/zqcBffbMZn
--WKLeak_sDOnCKTopI5 : https://discord.gg/zqcBffbMZn
--WKLeaksmcOnxhTopLU : https://discord.gg/zqcBffbMZn
--WKLeak-WvOnD2Top@c : https://discord.gg/zqcBffbMZn
--WKLeak-PFOn1ATopj$ : https://discord.gg/zqcBffbMZn
