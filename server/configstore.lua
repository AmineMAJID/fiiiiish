--[[   -- https://discord.gg/zqcBffbMZn ]]
local TABLE_NAME = "qs_fisher_config"
local COMPUTED_TOP_KEYS = {
    Framework = true,
    Vehiclekeys = true,
    Inventory = true,
    InventoryMetadata = true,
    Languages = true,
    Descriptions = true
}

local BaseConfigCopy = nil
local AppliedConfig = {}
local LiveOverrides = {}

local ALLOWED_OPTIONS = {
    TargetScript = {
        { "ox", "ox_target" },
        { "qb", "qb-target" }
    },
    PlayerNameSource = {
        { "character", "Character name" },
        { "cfx", "FiveM name" },
        { "both", "Character name (FiveM name)" }
    },
    CurrencyPosition = {
        { "prefix", "$500" },
        { "suffix", "500 $" }
    },
    WeightUnit = {
        { "kg", "Kilograms" },
        { "lb", "Pounds" }
    },
    MissionPayout = {
        { "members", "Every member gets the full reward" },
        { "split", "The reward is split between them" }
    },
    ["Speargun.Breath.Shop"] = {
        { "auto", "Hidden while the other resource is running" },
        { "always", "Always on the shelf" },
        { "never", "Never sold here" }
    }
}

local LANGUAGE_LABELS = {
    en = "English",
    it = "Italiano",
    es = "Español",
    fr = "Français",
    pt = "Português",
    de = "Deutsch",
    ru = "Русский",
    tr = "Türkçe"
}

local MAX_SCHEMA_DEPTH = 8

function IsVectorType(val)
    local t = type(val)
    return t == "vector3" or t == "vector4" or t == "vector2"
end

function VectorToTable(val)
    local res = {
        __vec = true,
        x = val.x,
        y = val.y
    }
    local t = type(val)
    if t == "vector3" or t == "vector4" then
        res.z = val.z
    end
    if t == "vector4" then
        res.w = val.w
    end
    return res
end

function TableToVector(tbl)
    if tbl.w ~= nil then
        return vector4(tbl.x, tbl.y, tbl.z, tbl.w)
    elseif tbl.z ~= nil then
        return vector3(tbl.x, tbl.y, tbl.z)
    end
    return vector2(tbl.x, tbl.y)
end

function SerializeVectors(val)
    if IsVectorType(val) then
        return VectorToTable(val)
    end
    if type(val) ~= "table" then
        return val
    end
    local res = {}
    for k, v in pairs(val) do
        if type(v) ~= "function" then
            res[k] = SerializeVectors(v)
        end
    end
    return res
end

function DeserializeVectors(val)
    if type(val) ~= "table" then
        return val
    end
    if val.__vec then
        return TableToVector(val)
    end
    local res = {}
    for k, v in pairs(val) do
        res[k] = DeserializeVectors(v)
    end
    return res
end

function SplitPath(path)
    local parts = {}
    for part in tostring(path):gmatch("[^%.]+") do
        parts[#parts + 1] = tonumber(part) or part
    end
    return parts
end

function GetPathValue(tbl, path)
    local current = tbl
    for _, key in ipairs(SplitPath(path)) do
        if type(current) ~= "table" then
            return nil
        end
        current = current[key]
    end
    return current
end

function SetPathValue(tbl, path, val)
    local parts = SplitPath(path)
    local current = tbl
    for i = 1, #parts - 1 do
        local key = parts[i]
        if current[key] == nil then
            current[key] = {}
        end
        if type(current[key]) ~= "table" then
            return false
        end
        current = current[key]
    end
    current[parts[#parts]] = val
    return true
end

function CanSetPath(tbl, path)
    local parts = SplitPath(path)
    local current = tbl
    if type(current) ~= "table" then
        return false
    end
    for i = 1, #parts - 1 do
        local key = parts[i]
        current = current[key]
        if current == nil then
            return true
        end
        if type(current) ~= "table" then
            return false
        end
    end
    return type(current) == "table"
end

function DeepCopy(val)
    if IsVectorType(val) then
        return val
    end
    if type(val) ~= "table" then
        return val
    end
    local res = {}
    for k, v in pairs(val) do
        res[k] = DeepCopy(v)
    end
    return res
end

function InferShape(val)
    if IsVectorType(val) then
        return type(val) == "vector4" and "vector4" or "vector3"
    end
    local t = type(val)
    if t == "boolean" or t == "number" or t == "string" then
        return t
    end
    if t ~= "table" then
        return nil
    end
    if #val > 0 then
        return type(val[1]) == "table" and "list" or "array"
    end
    return "group"
end

function GetFieldDescription(path)
    local desc = Config.Descriptions
    if type(desc) == "table" then
        return desc[path]
    end
    return nil
end

function GetLanguageOptions()
    local keys = {}
    for lang in pairs(Config.Languages or {}) do
        keys[#keys + 1] = lang
    end
    table.sort(keys)

    local options = {}
    for _, lang in ipairs(keys) do
        options[#options + 1] = {
            value = lang,
            label = LANGUAGE_LABELS[lang] or lang
        }
    end
    return options
end

function GetFieldOptions(path)
    if path == "Language" then
        return GetLanguageOptions()
    end
    local entries = ALLOWED_OPTIONS[path]
    if not entries then
        return nil
    end

    local list = {}
    for _, opt in ipairs(entries) do
        list[#list + 1] = {
            value = opt[1],
            label = opt[2]
        }
    end
    return list
end

function StoredConfigAllows(path, val)
    local options = GetFieldOptions(path)
    if not options then
        return nil
    end
    for _, opt in ipairs(options) do
        if opt.value == val then
            return true
        end
    end
    return false
end

function BuildSchemaNode(val, path, depth, visited)
    local shape = InferShape(val)
    if not shape then
        return nil
    end
    if depth > MAX_SCHEMA_DEPTH then
        return nil
    end

    if type(val) == "table" then
        visited = visited or {}
        if visited[val] then
            return nil
        end
        visited[val] = true
    end

    local node = {
        path = path,
        shape = shape,
        help = GetFieldDescription(path)
    }

    if shape == "string" then
        node.options = GetFieldOptions(path)
    end

    if shape == "group" or (shape == "list" and depth < 3) then
        node.children = {}
        local keys = {}
        for k in pairs(val) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)

        for _, k in ipairs(keys) do
            local childPath = (path == "") and tostring(k) or (path .. "." .. tostring(k))
            local childNode = BuildSchemaNode(val[k], childPath, depth + 1, visited)
            if childNode then
                childNode.key = k
                node.children[#node.children + 1] = childNode
            end
        end

        if type(val) == "table" then
            visited[val] = nil
        end

        if #node.children == 0 and shape == "group" then
            return nil
        end
    else
        node.value = SerializeVectors(val)
    end

    if shape == "list" or shape == "array" then
        node.value = SerializeVectors(val)
        node.count = #val
    end

    return node
end

function GetEffectiveConfig()
    local res = DeepCopy(BaseConfigCopy or Config)
    for path, val in pairs(LiveOverrides) do
        SetPathValue(res, path, DeepCopy(val))
    end
    return res
end

function AreValuesEqual(a, b)
    if a == b then
        return true
    end
    if a == nil or b == nil then
        return false
    end
    local ok1, jsonA = pcall(json.encode, SerializeVectors(a))
    local ok2, jsonB = pcall(json.encode, SerializeVectors(b))
    return ok1 and ok2 and jsonA == jsonB
end

function StoredConfigNeedsRestart()
    for path, liveVal in pairs(LiveOverrides) do
        if not AreValuesEqual(liveVal, AppliedConfig[path]) then
            return true
        end
    end
    for path in pairs(AppliedConfig) do
        if LiveOverrides[path] == nil then
            return true
        end
    end
    return false
end

function BuildConfigSchema()
    local effective = GetEffectiveConfig()
    local tree = {}
    local topKeys = {}

    for k, v in pairs(effective) do
        if not COMPUTED_TOP_KEYS[k] and type(v) ~= "function" then
            topKeys[#topKeys + 1] = k
        end
    end
    table.sort(topKeys)

    for _, k in ipairs(topKeys) do
        local node = BuildSchemaNode(effective[k], k, 1, {})
        if node then
            node.key = k
            tree[#tree + 1] = node
        end
    end

    local overridden = {}
    for k in pairs(LiveOverrides) do
        overridden[#overridden + 1] = k
    end

    return {
        tree = tree,
        overridden = overridden,
        restartOwed = StoredConfigNeedsRestart()
    }
end

function EnsureConfigTable()
    MySQL.query.await(string.format([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `path` VARCHAR(191) NOT NULL,
            `value` LONGTEXT NOT NULL,
            `updated_by` VARCHAR(64) DEFAULT NULL,
            `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`path`) USING BTREE
        ) ENGINE=InnoDB COLLATE='utf8mb4_general_ci'
    ]], TABLE_NAME))
end

function ApplyConfigValue(path, val)
    return SetPathValue(Config, path, val)
end

function LoadStoredConfig()
    BaseConfigCopy = DeepCopy(Config)

    local ok, rows = pcall(function()
        EnsureConfigTable()
        return MySQL.query.await(string.format("SELECT `path`, `value` FROM `%s`", TABLE_NAME)) or {}
    end)

    if not ok then
        print(string.format("^1[qs-fishingjob]^0 could not read the saved configuration: %s", tostring(rows)))
        return
    end

    local appliedCount = 0
    local ignoredPaths = {}
    local catchDecisionOverrides = {}

    for _, row in ipairs(rows) do
        local decodedOk, parsedVal = pcall(json.decode, row.value)
        if decodedOk then
            parsedVal = DeserializeVectors(parsedVal)
            if ApplyConfigValue(row.path, parsedVal) then
                AppliedConfig[row.path] = parsedVal
                LiveOverrides[row.path] = parsedVal
                appliedCount = appliedCount + 1
                if row.path == "CatchDecision.Enabled" then
                    catchDecisionOverrides[#catchDecisionOverrides + 1] = tostring(parsedVal)
                end
            else
                ignoredPaths[#ignoredPaths + 1] = row.path
            end
        else
            ignoredPaths[#ignoredPaths + 1] = row.path
        end
    end

    -- The keep-it window is the one setting people report as "not working" when it
    -- has simply been switched off from the admin panel. Name it when it happens.
    if #catchDecisionOverrides > 0 and Config.CatchDecision then
        if Config.CatchDecision.Enabled == false then
            print(("^3[qs-fishingjob]^0 a saved setting in `%s` turns CatchDecision off, so the keep-it window will not open.\n"
                .. "  It overrides config.lua. Delete that row or set it back to true from the admin panel.\n"
                .. "    DELETE FROM `%s` WHERE `path` = 'CatchDecision.Enabled';"):format(TABLE_NAME, TABLE_NAME))
        else
            print(("^2[qs-fishingjob]^0 CatchDecision settings applied from `%s` (Enabled = %s).")
                :format(TABLE_NAME, tostring(Config.CatchDecision.Enabled)))
        end
    end

    if appliedCount > 0 then
        print(string.format("^2[qs-fishingjob]^0 %d saved setting(s) applied over config.lua.", appliedCount))
    end
    if #ignoredPaths > 0 then
        print(string.format("^3[qs-fishingjob]^0 %d saved setting(s) no longer fit this config and were ignored: %s", #ignoredPaths, table.concat(ignoredPaths, ", ")))
    end
end

function StoredConfigPayload()
    local list = {}
    for path, val in pairs(AppliedConfig) do
        list[#list + 1] = {
            path = path,
            value = SerializeVectors(val)
        }
    end
    return list
end

function StoredConfigValue(path)
    if LiveOverrides[path] ~= nil then
        return SerializeVectors(LiveOverrides[path])
    end

    local val = GetPathValue(BaseConfigCopy, path)
    if val == nil then
        return nil
    end

    val = DeepCopy(val)
    if type(val) == "table" then
        local prefix = path .. "."
        for ovPath, ovVal in pairs(LiveOverrides) do
            if ovPath:sub(1, #prefix) == prefix then
                local subKey = ovPath:sub(#prefix + 1)
                SetPathValue(val, subKey, DeepCopy(ovVal))
            end
        end
    end

    return SerializeVectors(val)
end

function IsSequentialArray(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    local count = 0
    for k in pairs(tbl) do
        if type(k) == "number" and k % 1 == 0 and k >= 1 then
            count = count + 1
        else
            return false
        end
    end
    return count == #tbl
end

function CoerceValue(targetTemplate, incomingVal)
    if IsVectorType(targetTemplate) then
        local t = type(incomingVal) == "table" and incomingVal or {}
        local x = tonumber(t.x) or 0.0
        local y = tonumber(t.y) or 0.0
        local z = tonumber(t.z) or 0.0
        local w = tonumber(t.w) or 0.0
        local shape = type(targetTemplate)
        if shape == "vector4" then
            return vector4(x, y, z, w)
        elseif shape == "vector2" then
            return vector2(x, y)
        end
        return vector3(x, y, z)
    end

    if type(targetTemplate) == "table" and type(incomingVal) == "table" then
        local res = {}
        for k, v in pairs(incomingVal) do
            local actualKey = k
            if type(k) == "string" then
                local numKey = tonumber(k)
                if numKey and targetTemplate[numKey] ~= nil then
                    actualKey = numKey
                end
            end
            res[actualKey] = CoerceValue(targetTemplate[actualKey], v)
        end
        return res
    end

    return incomingVal
end

function ValidateValueShape(template, val)
    if IsVectorType(template) then
        return type(val) == "table" or IsVectorType(val)
    end

    local shape = InferShape(template)
    if shape == nil then
        return true
    end

    if shape == "boolean" or shape == "number" or shape == "string" then
        return type(val) == shape
    end

    if type(val) ~= "table" then
        return false
    end

    if IsSequentialArray(template) ~= IsSequentialArray(val) then
        return false
    end

    if shape == "list" then
        local childTemplate = template[1]
        for _, item in ipairs(val) do
            if not ValidateValueShape(childTemplate, item) then
                return false
            end
        end
        return true
    end

    for k, childTemplate in pairs(template) do
        if val[k] ~= nil and not ValidateValueShape(childTemplate, val[k]) then
            return false
        end
    end

    return true
end

function CheckValueCompatibility(path, val)
    local template = GetPathValue(BaseConfigCopy, path)
    if template == nil then
        return true
    end
    if InferShape(val) == nil and not IsVectorType(template) then
        return false
    end
    return ValidateValueShape(template, val)
end

function SetStoredConfig(path, val, updatedBy)
    if type(path) ~= "string" or path == "" then
        return false, "path"
    end

    local topKey = SplitPath(path)[1]
    if COMPUTED_TOP_KEYS[topKey] then
        return false, "computed"
    end

    local existing = GetPathValue(BaseConfigCopy, path)
    if existing == nil and GetPathValue(Config, path) == nil then
        return false, "unknown"
    end

    val = CoerceValue(GetPathValue(BaseConfigCopy, path), DeserializeVectors(val))
    if not CheckValueCompatibility(path, val) then
        return false, "shape"
    end

    if StoredConfigAllows(path, val) == false then
        return false, "choice"
    end

    if not CanSetPath(BaseConfigCopy or Config, path) then
        return false, "path"
    end

    local ok, err = pcall(function()
        MySQL.query.await(
            string.format("REPLACE INTO `%s` (`path`, `value`, `updated_by`) VALUES (?, ?, ?)", TABLE_NAME),
            { path, json.encode(SerializeVectors(val)), updatedBy or "?" }
        )
    end)

    if not ok then
        print(string.format("^1[qs-fishingjob]^0 could not save %s: %s", path, tostring(err)))
        return false, "database"
    end

    LiveOverrides[path] = val
    return true
end

function ResetStoredConfig(path)
    if type(path) ~= "string" or path == "" then
        return false, "path"
    end

    if GetPathValue(BaseConfigCopy, path) == nil and LiveOverrides[path] == nil then
        return false, "unknown"
    end

    local ok, err = pcall(function()
        MySQL.query.await(string.format("DELETE FROM `%s` WHERE `path` = ?", TABLE_NAME), { path })
    end)

    if not ok then
        print(string.format("^1[qs-fishingjob]^0 could not reset %s: %s", path, tostring(err)))
        return false, "database"
    end

    LiveOverrides[path] = nil
    return true
end

function ResetAllStoredConfig()
    local keys = {}
    for k in pairs(LiveOverrides) do
        keys[#keys + 1] = k
    end
    local count = 0
    for _, k in ipairs(keys) do
        if ResetStoredConfig(k) then
            count = count + 1
        end
    end
    return count
end

function readPathForTest(path)
    return GetPathValue(Config, path)
end
--WKLeak_afOn9qTopO7 : https://discord.gg/zqcBffbMZn
--WKLeak-VAOnw1Topcs : https://discord.gg/zqcBffbMZn
--WKLeakv@OnKITopiI : https://discord.gg/zqcBffbMZn
--WKLeaks94OnLxTopAH : https://discord.gg/zqcBffbMZn
--WKLeak__xOn6nTop2# : https://discord.gg/zqcBffbMZn
