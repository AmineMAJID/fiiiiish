--[[   -- https://discord.gg/zqcBffbMZn ]]
local BASE_TABLE = "qs_fisher"

local REQUIRED_COLUMNS = {
    { "total_experience", "INT(10) UNSIGNED NOT NULL DEFAULT 0" },
    { "total_earnings", "INT(10) UNSIGNED NOT NULL DEFAULT 0" },
    { "season_experience", "INT(10) UNSIGNED NOT NULL DEFAULT 0" },
    { "season_earnings", "INT(10) UNSIGNED NOT NULL DEFAULT 0" },
    { "daily_experience", "INT(10) UNSIGNED NOT NULL DEFAULT 0" },
    { "daily_earnings", "INT(10) UNSIGNED NOT NULL DEFAULT 0" }
}

local JOB_LABELS = {
    fisher = "Fisher"
}

-- Columns every install of the records table must have. Older builds shipped a
-- different shape (best_length, no caught/released/trophies), and because the
-- CREATE TABLE below is IF NOT EXISTS, an old table is never reshaped by itself.
-- That used to break the whole catch: the SELECT in server/fishstats.lua threw
-- "Unknown column 'caught'", which aborted resolveCatch before the items and the
-- keep-it panel were ever produced.
local RECORD_COLUMNS = {
    { "fish",         "VARCHAR(64) NOT NULL DEFAULT '' COLLATE 'utf8mb4_general_ci'" },
    { "caught",       "INT(10) UNSIGNED NOT NULL DEFAULT 0" },
    { "released",     "INT(10) UNSIGNED NOT NULL DEFAULT 0" },
    { "best_weight",  "DECIMAL(8,2) NOT NULL DEFAULT 0" },
    { "best_quality", "DECIMAL(4,3) NOT NULL DEFAULT 0" },
    { "best_at",      "DATETIME NULL DEFAULT NULL" },
    { "trophies",     "INT(10) UNSIGNED NOT NULL DEFAULT 0" }
}

local schemaState = "idle"

function TableColumns(tableName)
    local rows = MySQL.query.await([[
        SELECT COLUMN_NAME FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
    ]], { tableName }) or {}

    local columns = {}
    for _, row in ipairs(rows or {}) do
        local name = row.COLUMN_NAME or row.column_name
        if name then
            columns[string.lower(name)] = true
        end
    end
    return columns
end

function EnsureTableColumns(tableName, columnDefs)
    local existing = TableColumns(tableName)
    local added = 0

    for _, def in ipairs(columnDefs) do
        local columnName, columnType = def[1], def[2]
        if not existing[string.lower(columnName)] then
            local ok, err = pcall(function()
                MySQL.query.await(string.format("ALTER TABLE `%s` ADD COLUMN `%s` %s", tableName, columnName, columnType))
            end)
            if ok then
                added = added + 1
                print(string.format("^2[qs-fishingjob]^0 added missing column %s.%s", tableName, columnName))
            else
                print(string.format("^1[qs-fishingjob]^0 could not add column %s.%s: %s", tableName, columnName, tostring(err)))
            end
        end
    end

    return added
end

function IndexColumns(tableName, indexName)
    local rows = MySQL.query.await([[
        SELECT COLUMN_NAME FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?
        ORDER BY SEQ_IN_INDEX
    ]], { tableName, indexName }) or {}

    local list = {}
    for _, row in ipairs(rows or {}) do
        list[#list + 1] = string.lower(row.COLUMN_NAME or row.column_name or "")
    end
    return list
end

-- ON DUPLICATE KEY UPDATE only does what it says if a UNIQUE/PRIMARY key covers
-- (identifier, fish). An old table keyed on identifier alone would grow one row
-- per catch instead of updating it.
function EnsureRecordUniqueKey()
    local primary = IndexColumns(BASE_TABLE .. "_records", "PRIMARY")
    if #primary == 2 and primary[1] == "identifier" and primary[2] == "fish" then
        return
    end

    local existing = IndexColumns(BASE_TABLE .. "_records", "uniq_identifier_fish")
    if #existing == 2 and existing[1] == "identifier" and existing[2] == "fish" then
        return
    end

    -- Primary key on identifier alone: the table holds one row per player from a
    -- build that did not track individual species. It cannot hold per-fish records,
    -- so say so plainly instead of quietly writing nonsense into it.
    if #primary == 1 and primary[1] == "identifier" then
        print(string.format("^3[qs-fishingjob]^0 `%s_records` is keyed on identifier only (old format).\n"
            .. "  Per-fish records cannot be stored in it. Emptying it lets the new keys be added:\n"
            .. "    TRUNCATE TABLE `%s_records`;\n"
            .. "  then restart the resource.", BASE_TABLE, BASE_TABLE))
        return
    end

    local ok, err = pcall(function()
        MySQL.query.await(string.format(
            "ALTER TABLE `%s_records` ADD UNIQUE KEY `uniq_identifier_fish` (`identifier`, `fish`)", BASE_TABLE))
    end)

    if ok then
        print(string.format("^2[qs-fishingjob]^0 added the (identifier, fish) unique key to %s_records.", BASE_TABLE))
    else
        print(string.format("^3[qs-fishingjob]^0 could not add a unique key to %s_records (duplicate rows?): %s\n"
            .. "  Personal records will overwrite nothing until the duplicates are cleaned up.", BASE_TABLE, tostring(err)))
    end
end

function AlignCollation()
    local usersTable = "users"
    local idColumn = "identifier"
    if Config.Framework == "qb" then
        usersTable = "players"
        idColumn = "citizenid"
    end

    local ok, targetCollation = pcall(function()
        local query = [[
            SELECT COLLATION_NAME FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
        ]]
        return MySQL.scalar.await(query, { usersTable, idColumn })
    end)

    if not ok or not targetCollation then
        return
    end

    local query = [[
        SELECT TABLE_NAME, COLUMN_TYPE, IS_NULLABLE
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME LIKE ?
          AND COLUMN_NAME = 'identifier'
          AND COLLATION_NAME IS NOT NULL
          AND COLLATION_NAME <> ?
    ]]
    local columnsToAlign = MySQL.query.await(query, { BASE_TABLE .. "%", targetCollation })
    if not columnsToAlign or #columnsToAlign == 0 then
        return
    end

    for _, col in ipairs(columnsToAlign) do
        local nullability = (col.IS_NULLABLE == "NO") and "NOT NULL" or "NULL"
        local alterSql = string.format("ALTER TABLE `%s` MODIFY `identifier` %s COLLATE %s %s",
            col.TABLE_NAME, col.COLUMN_TYPE, targetCollation, nullability)
        local success = pcall(function()
            MySQL.query.await(alterSql)
        end)
        if not success then
            print(string.format("^1[qs-fishingjob]^0 could not align `%s`.`identifier` to %s (%s.%s uses it).\n"
                .. "  The leaderboard will fail with \"Illegal mix of collations\" until it matches. Run by hand:\n"
                .. "    %s;", col.TABLE_NAME, targetCollation, usersTable, idColumn, alterSql))
            return
        end
    end

    print(string.format("^2[qs-fishingjob]^0 aligned %d identifier column(s) to %s, matching %s.%s.",
        #columnsToAlign, targetCollation, usersTable, idColumn))
end

function CreateTables()
    MySQL.query.await(string.format([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `identifier` VARCHAR(46) NOT NULL COLLATE 'utf8mb4_general_ci',
            `level` INT(10) UNSIGNED NOT NULL DEFAULT 1,
            `experience` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            `total_experience` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            `total_earnings` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            `season_experience` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            `season_earnings` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            `daily_experience` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            `daily_earnings` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (`identifier`) USING BTREE
        ) ENGINE=InnoDB COLLATE='utf8mb4_general_ci'
    ]], BASE_TABLE))

    MySQL.query.await(string.format([[
        CREATE TABLE IF NOT EXISTS `%s_resets` (
            `identifier` VARCHAR(46) NOT NULL COLLATE 'utf8mb4_general_ci',
            `last_daily_reset` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `last_season_reset` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`) USING BTREE
        ) ENGINE=InnoDB COLLATE='utf8mb4_general_ci'
    ]], BASE_TABLE))

    MySQL.query.await(string.format([[
        CREATE TABLE IF NOT EXISTS `%s_rewards` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `identifier` VARCHAR(255) NOT NULL,
            `reward_type` VARCHAR(50) NOT NULL,
            `reward_amount` INT NOT NULL
        ) ENGINE=InnoDB COLLATE='utf8mb4_general_ci'
    ]], BASE_TABLE))

    MySQL.query.await(string.format([[
        CREATE TABLE IF NOT EXISTS `%s_leaderboard_winners` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `position` INT NOT NULL,
            `identifier` VARCHAR(255) NOT NULL,
            `reward_amount` INT NOT NULL,
            `reward_type` VARCHAR(10) NOT NULL,
            UNIQUE KEY (`position`, `reward_type`)
        ) ENGINE=InnoDB COLLATE='utf8mb4_general_ci'
    ]], BASE_TABLE))

    MySQL.query.await(string.format([[
        CREATE TABLE IF NOT EXISTS `%s_records` (
            `identifier` VARCHAR(46) NOT NULL COLLATE 'utf8mb4_general_ci',
            `fish` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `caught` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            `released` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            `best_weight` DECIMAL(8,2) NOT NULL DEFAULT 0,
            `best_quality` DECIMAL(4,3) NOT NULL DEFAULT 0,
            `best_at` DATETIME NULL DEFAULT NULL,
            `trophies` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (`identifier`, `fish`) USING BTREE,
            INDEX `idx_best_weight` (`fish`, `best_weight`)
        ) ENGINE=InnoDB COLLATE='utf8mb4_general_ci'
    ]], BASE_TABLE))

    local legacyCount = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = ?
          AND COLUMN_NAME = 'best_length'
    ]], { BASE_TABLE .. "_records" }) or 0

    if legacyCount > 0 then
        MySQL.query.await(string.format([[
            ALTER TABLE `%s_records` DROP COLUMN `best_length`
        ]], BASE_TABLE))
        print("^2[qs-fishingjob]^0 dropped the legacy best_length column; catches are measured by weight only now.")
    end

    EnsureTableColumns(BASE_TABLE .. "_records", RECORD_COLUMNS)
    EnsureRecordUniqueKey()

    MySQL.query.await(string.format([[
        CREATE TABLE IF NOT EXISTS `%s_tournaments` (
            `identifier` VARCHAR(46) NOT NULL COLLATE 'utf8mb4_general_ci',
            `wins_heaviest` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            `wins_most` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            `wins_total` INT(10) UNSIGNED NOT NULL DEFAULT 0,
            `last_win` DATETIME NULL DEFAULT NULL,
            PRIMARY KEY (`identifier`) USING BTREE,
            INDEX `idx_wins_total` (`wins_total`)
        ) ENGINE=InnoDB COLLATE='utf8mb4_general_ci'
    ]], BASE_TABLE))

    MySQL.query.await(string.format([[
        CREATE TABLE IF NOT EXISTS `%s_crabtraps` (
            `id` INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(46) NOT NULL COLLATE 'utf8mb4_general_ci',
            `x` FLOAT NOT NULL,
            `y` FLOAT NOT NULL,
            `sea_z` FLOAT NOT NULL,
            `water_z` FLOAT NOT NULL,
            `band` VARCHAR(16) NOT NULL COLLATE 'utf8mb4_general_ci',
            `placed_at` INT(10) UNSIGNED NOT NULL,
            PRIMARY KEY (`id`) USING BTREE,
            INDEX `idx_owner` (`identifier`)
        ) ENGINE=InnoDB COLLATE='utf8mb4_general_ci'
    ]], BASE_TABLE))

    MySQL.query.await(string.format([[
        CREATE TABLE IF NOT EXISTS `%s_achievements` (
            `identifier` VARCHAR(46) NOT NULL COLLATE 'utf8mb4_general_ci',
            `achievement` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `unlocked_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `claimed_at` DATETIME NULL DEFAULT NULL,
            PRIMARY KEY (`identifier`, `achievement`) USING BTREE
        ) ENGINE=InnoDB COLLATE='utf8mb4_general_ci'
    ]], BASE_TABLE))

    local claimedColCount = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = ?
          AND COLUMN_NAME = 'claimed_at'
    ]], { BASE_TABLE .. "_achievements" }) or 0

    if claimedColCount == 0 then
        MySQL.query.await(string.format([[
            ALTER TABLE `%s_achievements`
            ADD COLUMN `claimed_at` DATETIME NULL DEFAULT NULL
        ]], BASE_TABLE))
        MySQL.query.await(string.format([[
            UPDATE `%s_achievements` SET `claimed_at` = `unlocked_at`
        ]], BASE_TABLE))
        print("^2[qs-fishingjob]^0 achievements are claimed at the manager now. Everything already unlocked was marked as paid, because it was.")
    end
end

function VerifyColumns()
    local existingColumnsResult = MySQL.query.await([[
        SELECT COLUMN_NAME FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
    ]], { BASE_TABLE }) or {}

    local existingColumns = {}
    for _, col in ipairs(existingColumnsResult) do
        local name = col.COLUMN_NAME or col.column_name or ""
        existingColumns[string.lower(name)] = true
    end

    for _, req in ipairs(REQUIRED_COLUMNS) do
        local colName = req[1]
        local colDef = req[2]
        if not existingColumns[colName] then
            MySQL.query.await(string.format("ALTER TABLE `%s` ADD COLUMN `%s` %s", BASE_TABLE, colName, colDef))
            print(string.format("^2[%s]^0 Added missing column %s.%s", GetCurrentResourceName(), BASE_TABLE, colName))
        end
    end
end

function RegisterESXJobs()
    if Config.Framework ~= "esx" then
        return
    end
    local fisherJobs = Config.FisherJob or {}
    for jobName, _ in pairs(fisherJobs) do
        local label = JOB_LABELS[jobName] or (jobName:sub(1, 1):upper() .. jobName:sub(2))
        local jobExists = MySQL.single.await("SELECT name FROM jobs WHERE name = ?", { jobName })
        if not jobExists then
            MySQL.insert.await("INSERT INTO jobs (name, label) VALUES (?, ?)", { jobName, label })
            print(string.format("^2[%s]^0 Registered the ESX job \"%s\"", GetCurrentResourceName(), jobName))
        end

        local gradeExists = MySQL.single.await("SELECT job_name FROM job_grades WHERE job_name = ? AND grade = 0", { jobName })
        if not gradeExists then
            MySQL.insert.await("INSERT INTO job_grades (job_name, grade, name, label, salary, skin_male, skin_female) VALUES (?, 0, ?, ?, ?, ?, ?)",
                { jobName, "novice", "Novice", 10, "{}", "{}" })
        end
    end
end

function EnsureSchema()
    if schemaState == "ready" then
        return
    end
    if schemaState == "running" then
        repeat
            Wait(50)
        until schemaState ~= "running"
        return
    end

    schemaState = "running"

    -- Every step gets its own pcall: a failure while migrating the records table
    -- must not skip the collation alignment (or the other way round).
    local steps = {
        { name = "create the tables", fn = CreateTables },
        { name = "verify the columns", fn = VerifyColumns },
        { name = "align the collations", fn = AlignCollation }
    }

    local failures = 0
    for _, step in ipairs(steps) do
        local ok, err = pcall(step.fn)
        if not ok then
            failures = failures + 1
            print(string.format("^1[%s]^0 Could not %s: %s", GetCurrentResourceName(), step.name, tostring(err)))
        end
    end

    local esxOk, esxErr = pcall(RegisterESXJobs)

    if LoadStoredConfig then
        pcall(LoadStoredConfig)
    end

    schemaState = "ready"

    if failures == 0 then
        print(string.format("^2[%s]^0 schema ready.", GetCurrentResourceName()))
    end
    if not esxOk then
        print(string.format("^3[%s]^0 Could not register the ESX job rows: %s", GetCurrentResourceName(), tostring(esxErr)))
    end
end
--WKLeaksucOny1TopNK : https://discord.gg/zqcBffbMZn
--WKLeakmPOnSDTophA : https://discord.gg/zqcBffbMZn
--WKLeakL$OnHBTopsp : https://discord.gg/zqcBffbMZn
--WKLeaks9JOnNJTopJL : https://discord.gg/zqcBffbMZn
--WKLeak-qVOnkCTop@b : https://discord.gg/zqcBffbMZn
