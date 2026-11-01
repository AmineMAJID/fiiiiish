--[[   -- https://discord.gg/zqcBffbMZn ]]
if Config.Vehiclekeys ~= 'mono_carkeys' then
    return
end

function AddVehiclekeys(vehicle, plate, item)
    if not item then return end
    if type(vehicle) ~= 'string' then return end
    TriggerServerEvent('mono_carkeys:CreateKey', plate)
end

function RemoveVehiclekeys(vehicle, plate)
    if type(vehicle) ~= 'string' then return end
    TriggerServerEvent('mono_carkeys:DeleteKey', 1, plate)
end
--WKLeak-xKOnAmToplp : https://discord.gg/zqcBffbMZn
--WKLeakx!Ont@Tope6 : https://discord.gg/zqcBffbMZn
--WKLeaks5VOnGIToplH : https://discord.gg/zqcBffbMZn
--WKLeak_LTOni9TopZK : https://discord.gg/zqcBffbMZn
--WKLeak_TQOneXTopn! : https://discord.gg/zqcBffbMZn
