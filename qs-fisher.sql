INSERT IGNORE INTO `jobs` (name, label) VALUES
    ('fisher','Fisher')
;

INSERT IGNORE INTO `job_grades` (job_name, grade, name, label, salary, skin_male, skin_female) VALUES
    ('fisher',0,'novice','Novice',10,'{}','{}')
;

CREATE TABLE IF NOT EXISTS `qs_fisher` (
    `identifier` VARCHAR(46) NOT NULL COLLATE 'utf8mb4_general_ci',
    `level` INT(10) UNSIGNED NOT NULL DEFAULT '1',
    `experience` INT(10) UNSIGNED NOT NULL DEFAULT '0',
    `total_experience` INT(10) UNSIGNED NOT NULL DEFAULT '0',
    `total_earnings` INT(10) UNSIGNED NOT NULL DEFAULT '0',
    `season_experience` INT(10) UNSIGNED NOT NULL DEFAULT '0',
    `season_earnings` INT(10) UNSIGNED NOT NULL DEFAULT '0',
    `daily_experience` INT(10) UNSIGNED NOT NULL DEFAULT '0',
    `daily_earnings` INT(10) UNSIGNED NOT NULL DEFAULT '0',
    PRIMARY KEY (`identifier`) USING BTREE
)
ENGINE=InnoDB
COLLATE='utf8mb4_general_ci'
;

CREATE TABLE IF NOT EXISTS `qs_fisher_resets` (
    `identifier` VARCHAR(46) NOT NULL COLLATE 'utf8mb4_general_ci',
    `last_daily_reset` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_season_reset` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`) USING BTREE
)
ENGINE=InnoDB
COLLATE='utf8mb4_general_ci'
;

CREATE TABLE IF NOT EXISTS `qs_fisher_rewards` (
    id INT AUTO_INCREMENT PRIMARY KEY,
    identifier VARCHAR(255) NOT NULL,
    reward_type VARCHAR(50) NOT NULL,
    reward_amount INT NOT NULL
)
ENGINE=InnoDB
COLLATE='utf8mb4_general_ci'
;

CREATE TABLE IF NOT EXISTS `qs_fisher_leaderboard_winners` (
    id INT AUTO_INCREMENT PRIMARY KEY,
    position INT NOT NULL,
    identifier VARCHAR(255) NOT NULL,
    reward_amount INT NOT NULL,
    reward_type VARCHAR(10) NOT NULL,
    UNIQUE KEY (position, reward_type)
)
ENGINE=InnoDB
COLLATE='utf8mb4_general_ci'
;
