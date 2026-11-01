--[[   -- https://discord.gg/zqcBffbMZn ]]
function GetWebhookConfig()
    return Config.Webhooks or {}
end

function GetWebhookUrl(eventType)
    local config = GetWebhookConfig()
    if not config.Enabled then
        return nil
    end
    local events = config.Events or {}
    local eventTarget = events[eventType]
    if not eventTarget then
        return nil
    end
    local url = (type(eventTarget) == "string" and eventTarget ~= "") and eventTarget or config.Url
    if type(url) ~= "string" or url == "" or not url:find("^https?://") then
        return nil
    end
    return url
end

function GetPlayerInfo(source)
    local srcNum = tonumber(source)
    if not srcNum then
        return "console", "-"
    end
    local name = GetPlayerName(srcNum) or ("id " .. tostring(srcNum))
    local identifier = (GetPlayeridentifier and GetPlayeridentifier(srcNum)) or "-"
    return string.format("%s (%s)", name, srcNum), identifier
end

local WebhookColors = {
    MissionStarted = 3447003,
    MissionFinished = 5763719,
    MissionAbandoned = 15548997,
    MoneyPaid = 15844367,
    ExperienceGiven = 10181046,
    ConfigChanged = 9807270
}

function SendWebhook(eventType, source, title, description, fields)
    local webhookUrl = GetWebhookUrl(eventType)
    if not webhookUrl then
        return
    end
    local playerName, playerIdentifier = GetPlayerInfo(source)
    local config = GetWebhookConfig()
    local color = WebhookColors[eventType] or tonumber(config.Color) or 3447003
    local embed = {
        title = title,
        description = description,
        color = color,
        fields = fields or {},
        footer = {
            text = string.format("%s  ·  %s", playerName, playerIdentifier)
        }
    }
    if config.Timestamp ~= false then
        embed.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    end
    local avatar = config.Avatar
    local payload = {
        username = config.Name or "qs-fishingjob",
        avatar_url = (avatar ~= "" and avatar) or nil,
        embeds = { embed }
    }
    PerformHttpRequest(webhookUrl, function() end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })
end

function WebhookField(name, value, inline)
    if value == nil or value == "" then
        return nil
    end
    return {
        name = name,
        value = tostring(value),
        inline = inline ~= false
    }
end
--WKLeak-PPOn5HTopUy : https://discord.gg/zqcBffbMZn
--WKLeak-a0OniUTopv5 : https://discord.gg/zqcBffbMZn
--WKLeak_yOnp3Top#j : https://discord.gg/zqcBffbMZn
--WKLeaksfAOngMTopCl : https://discord.gg/zqcBffbMZn
--WKLeak_H9On1CTop5E : https://discord.gg/zqcBffbMZn
