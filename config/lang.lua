--[[
    Lang() — the translation lookup used by every other file.

    Kept in config/ so a server owner can see it next to the language tables.
    It reads Config.Languages at CALL time, not at load time, so the order the
    config files are loaded in does not matter.
]]

---@param key string
---@param ... any values for %s / %d placeholders
---@return string
function Lang(key, ...)
    local languages = Config and Config.Languages
    local language = languages and languages[Config.Language or 'en'] or nil

    local text = language and language[key] or tostring(key)

    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, text, ...)
        if ok then text = formatted end
    end

    return text
end

--- Backwards-compatible alias used by a few older client files.
GetLang = Lang
