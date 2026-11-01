--[[   -- https://discord.gg/zqcBffbMZn ]]
local CAM_DISTANCE = 1.4
local CAM_Z_OFFSET = 0.02
local CAM_FOV = 34.0
local CAM_RIGHT_OFFSET = 0.35
local CAM_TRANSITION_MS = 800
local USE_TIMECYCLE_BLUR = false
local FACIAL_MOOD = "mood_happy_1"
local MAX_INTERACT_DISTANCE = 6.0
local HEAD_BONE_INDEX = 31086

local DialogueGestures = {
    { dict = "gestures@m@standing@casual", name = "gesture_hello" },
    { dict = "gestures@m@standing@casual", name = "gesture_easy_a" },
    { dict = "gestures@m@standing@casual", name = "gesture_nod_yes_soft" },
    { dict = "gestures@m@standing@casual", name = "gesture_come_here_soft" },
    { dict = "gestures@m@standing@casual", name = "gesture_hand_down" }
}

local dialogueCam = nil
local isDialogueActive = false
local activePed = nil
local originalPedHeading = nil

function EnsureAnimDict(animDict)
    if HasAnimDictLoaded(animDict) then
        return true
    end
    RequestAnimDict(animDict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(animDict) do
        if GetGameTimer() > timeout then
            return false
        end
        Wait(0)
    end
    return true
end

function GetPedHeadPosition(ped)
    local boneCoords = GetPedBoneCoords(ped, HEAD_BONE_INDEX, 0.0, 0.0, 0.0)
    if boneCoords.x == 0.0 and boneCoords.y == 0.0 and boneCoords.z == 0.0 then
        return GetEntityCoords(ped) + vector3(0.0, 0.0, 0.62)
    end
    return boneCoords
end

function CreateDialogueCamera(ped)
    local headCoords = GetPedHeadPosition(ped)
    local headingRad = math.rad(GetEntityHeading(ped))
    local forward = vector3(-math.sin(headingRad), math.cos(headingRad), 0.0)
    local camPos = headCoords + (forward * CAM_DISTANCE) + vector3(0.0, 0.0, CAM_Z_OFFSET)
    local toHead = headCoords - camPos
    local toHeadFlat = vector3(toHead.x, toHead.y, 0.0)
    local flatLength = #toHeadFlat
    local rightDir = (flatLength > 0.001) and (toHeadFlat / flatLength) or forward
    local rightVec = vector3(rightDir.y, -rightDir.x, 0.0)
    local targetCoords = headCoords + (rightVec * CAM_RIGHT_OFFSET)

    local cam = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0, CAM_FOV, true, 0)
    PointCamAtCoord(cam, targetCoords.x, targetCoords.y, targetCoords.z)
    return cam
end

function PlayPedDialogueGestures(ped)
    CreateThread(function()
        Wait(250)
        while isDialogueActive and DoesEntityExist(ped) do
            local randomIndex = math.random(#DialogueGestures)
            local gesture = DialogueGestures[randomIndex]
            if gesture and EnsureAnimDict(gesture.dict) then
                TaskPlayAnim(ped, gesture.dict, gesture.name, 3.0, 3.0, -1, 48, 0.0, false, false, false)
            end
            local duration = math.random(2200, 3800)
            local elapsed = 0
            while isDialogueActive and elapsed < duration do
                Wait(100)
                elapsed = elapsed + 100
            end
        end
    end)
end

function HidePlayerPedDuringDialogue()
    CreateThread(function()
        while isDialogueActive do
            SetEntityLocallyInvisible(PlayerPedId())
            Wait(0)
        end
    end)
end

function StopPedDialogueCam(instant)
    isDialogueActive = false
    if activePed and DoesEntityExist(activePed) then
        ClearPedTasks(activePed)
        ClearFacialIdleAnimOverride(activePed)
        if originalPedHeading then
            SetEntityHeading(activePed, originalPedHeading)
        end
    end
    activePed = nil
    originalPedHeading = nil
    if dialogueCam then
        RenderScriptCams(false, not instant, instant and 0 or CAM_TRANSITION_MS, true, true)
        DestroyCam(dialogueCam, false)
        dialogueCam = nil
        if USE_TIMECYCLE_BLUR then
            ClearTimecycleModifier()
        end
    end
end

function StartPedDialogueCam(ped)
    if not ped and type(GetJobPed) == "function" then
        ped = GetJobPed()
    end
    if not ped or not DoesEntityExist(ped) then
        return
    end
    local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped))
    if distance > MAX_INTERACT_DISTANCE then
        return
    end
    StopPedDialogueCam(true)
    dialogueCam = CreateDialogueCamera(ped)
    SetCamActive(dialogueCam, true)
    RenderScriptCams(true, true, CAM_TRANSITION_MS, true, true)
    if USE_TIMECYCLE_BLUR then
        SetTimecycleModifier("hud_def_blur")
        SetTimecycleModifierStrength(1.0)
    end
    activePed = ped
    originalPedHeading = GetEntityHeading(ped)
    isDialogueActive = true
    TaskLookAtEntity(ped, PlayerPedId(), -1, 2048, 3)
    SetFacialIdleAnimOverride(ped, FACIAL_MOOD, 0)
    PlayPedDialogueGestures(ped)
    HidePlayerPedDuringDialogue()
end

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    isDialogueActive = false
    if dialogueCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(dialogueCam, false)
        dialogueCam = nil
    end
    ClearTimecycleModifier()
end)
--WKLeak_dNOnv8Top7a : https://discord.gg/zqcBffbMZn
--WKLeak_AEOnlBTopiC : https://discord.gg/zqcBffbMZn
--WKLeak-fPOnZuTop35 : https://discord.gg/zqcBffbMZn
--WKLeak-eMOnyBTop6d : https://discord.gg/zqcBffbMZn
--WKLeak_8dOn!MTophC : https://discord.gg/zqcBffbMZn
