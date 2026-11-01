-- qs-fishingjob — items for ESX
--
-- ESX reads its item list from this table, not from a Lua file, and refuses to
-- carry or to use anything that is not in it. Import this once.
--
-- Weight is 1 per item, matching every stock ESX item: Config.MaxWeight is 24.
-- The carry weights in items.lua are for ox_inventory and qs-inventory, which
-- count in grams; ESX does not.
--
-- INSERT IGNORE, so re-importing is safe and the three wood items shared with
-- qs-lumberjack are left exactly as that script created them.

INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
('wooden_rod', 'Wooden Rod', 1, 0, 1),
('carbon_rod', 'Carbon Rod', 1, 0, 1),
('composite_rod', 'Composite Rod', 1, 0, 1),
('tournament_rod', 'Tournament Rod', 1, 0, 1),
('master_rod', 'Master Rod', 1, 0, 1),
('fishing_kit', 'Fishing Kit', 1, 0, 1),
('barbed_hook', 'Barbed Hook', 1, 0, 1),
('float_bobber', 'Float Bobber', 1, 0, 1),
('circle_hook', 'Circle Hook', 1, 0, 1),
('spinning_reel', 'Spinning Reel', 1, 0, 1),
('monofilament_reel', 'Monofilament Reel', 1, 0, 1),
('graphite_reel', 'Graphite Reel', 1, 0, 1),
('deepsea_reel', 'Deep Sea Reel', 1, 0, 1),
('braided_line', 'Braided Line', 1, 0, 1),
('fluorocarbon_line', 'Fluorocarbon Line', 1, 0, 1),
('steel_leader', 'Steel Leader', 1, 0, 1),
('earthworms', 'Earthworms', 1, 0, 1),
('crickets', 'Crickets', 1, 0, 1),
('grasshopper', 'Grasshopper', 1, 0, 1),
('leech', 'Leech', 1, 0, 1),
('shrimp', 'Shrimp', 1, 0, 1),
('minnow', 'Minnow', 1, 0, 1),
('crab', 'Crab', 1, 0, 1),
('anguile', 'Anguile', 1, 0, 1),
('squid', 'Squid', 1, 0, 1),
('sardine', 'Sardine', 1, 0, 1),
('roach', 'Roach', 1, 0, 1),
('jacksmelt', 'Jacksmelt', 1, 0, 1),
('yellow_perch', 'Yellow Perch', 1, 0, 1),
('surfperch', 'Surfperch', 1, 0, 1),
('mackerel', 'Mackerel', 1, 0, 1),
('calico_bass', 'Calico Bass', 1, 0, 1),
('corbina', 'California Corbina', 1, 0, 1),
('rockfish', 'Rockfish', 1, 0, 1),
('eel', 'Eel', 1, 0, 1),
('pike', 'Pike', 1, 0, 1),
('catfish', 'Catfish', 1, 0, 1),
('sheephead', 'Sheephead', 1, 0, 1),
('salmon', 'Salmon', 1, 0, 1),
('lingcod', 'Lingcod', 1, 0, 1),
('barracuda', 'Barracuda', 1, 0, 1),
('california_halibut', 'California Halibut', 1, 0, 1),
('yellowtail', 'Yellowtail', 1, 0, 1),
('tuna', 'Tuna', 1, 0, 1),
('white_seabass', 'White Seabass', 1, 0, 1),
('horn_shark', 'Horn Shark', 1, 0, 1),
('pacific_halibut', 'Pacific Halibut', 1, 0, 1),
('stingray', 'Stingray', 1, 0, 1),
('swordfish', 'Swordfish', 1, 0, 1),
('boot', 'Old Boot', 1, 0, 1),
('crab_trap', 'Crab Trap', 1, 0, 1),
('brown_crab', 'Brown Crab', 1, 0, 1),
('striped_red_crab', 'Striped Red Crab', 1, 0, 1),
('yellow_crab', 'Yellow Crab', 1, 0, 1),
('drift_net', 'Drift Net', 1, 0, 1),
('trawl_net', 'Trawl Net', 1, 0, 1),
('deepsea_net', 'Deep Sea Net', 1, 0, 1),
('speargun', 'Speargun', 1, 0, 1),
('spear', 'Spear', 1, 0, 1),
('dive_tank', 'Dive Tank', 1, 0, 1),
('shark', 'Shark', 1, 0, 1),
('brochette_fish_raw', 'Raw Fish Skewer', 1, 0, 1),
('brochette_fish_cooked', 'Cooked Fish Skewer', 1, 0, 1),
('brochette_fish_burn', 'Burnt Fish Skewer', 1, 0, 1),
('skewer_grill_boat', 'Skewer Grill Boat', 1, 0, 1),
('oak_wood', 'Oak wood', 1, 0, 1),   -- also in qs-lumberjack
('pine_wood', 'Pine wood', 1, 0, 1),   -- also in qs-lumberjack
('maple_wood', 'Maple wood', 1, 0, 1);   -- also in qs-lumberjack
