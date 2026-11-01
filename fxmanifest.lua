--[[   -- https://discord.gg/zqcBffbMZn ]]
author "WKLeak"
description "WKLeak | https://discord.gg/zqcBffbMZn"

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

this_is_a_map 'yes'
title 'Quasar Fisher Job'
author 'Quasar Store'
version '3.2.1'

shared_scripts {
    '@ox_lib/init.lua',
    'config/*.lua'
}

ui_page 'web/build/index.html'

server_script '@oxmysql/lib/MySQL.lua'

files {
    'web/build/**',
    'sounds/*.mp3'
}

client_scripts {
    'client/marker.lua',
    'client/main.lua',
    'client/framework/*.lua',
    'client/vehiclekeys/*.lua',
    'client/clothing.lua',
    'client/target.lua',
    'client/dialogue.lua',
    'client/party.lua',
    'client/shop.lua',
    'client/leaderboard.lua',
    'client/fishing.lua',
    'client/boats.lua',
    'client/tournaments.lua',
    'client/hotspots.lua',
    'client/crabtraps.lua',
    'client/nets.lua',
    'client/speargun.lua',
    'client/campfire.lua',
    'client/foodboat.lua',
    'client/waterguide.lua',
    'client/adminconfig.lua',
    'client/achievements.lua',
}

server_scripts {
    'server/webhooks.lua',
    'server/framework/*.lua',
    'server/schema.lua',
    'server/configstore.lua',
    'server/missions.lua',
    'server/main.lua',
    'server/levelsystem.lua',
    'server/party.lua',
    'server/shop.lua',
    'server/fishstats.lua',
    'server/hotspots.lua',
    'server/fishing.lua',
    'server/boats.lua',
    'server/tournaments.lua',
    'server/adminconfig.lua',
    'server/crabtraps.lua',
    'server/nets.lua',
    'server/speargun.lua',
    'server/campfire.lua',
    'server/foodboat.lua',
    'server/achievements.lua',
}

escrow_ignore {
    'config/*.lua',
    'client/framework/*.lua',
    'client/vehiclekeys/*.lua',
    'client/clothing.lua',
    'client/target.lua',
    'server/framework/*.lua',
    'server/missions.lua',
    'items*.lua',
}

dependency '/assetpacks'
--WKLeakHCOn4KTopA6 : https://discord.gg/zqcBffbMZn
--WKLeak-3ZOnZGTopFN : https://discord.gg/zqcBffbMZn
--WKLeaksWKOnMJTopDq : https://discord.gg/zqcBffbMZn
--WKLeakNsOn2ETopIe : https://discord.gg/zqcBffbMZn
--WKLeak_m3OnzoTop_V : https://discord.gg/zqcBffbMZn
