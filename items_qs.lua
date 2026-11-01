--[[   -- https://discord.gg/zqcBffbMZn ]]
return {

-- Rods

['wooden_rod'] = { ['name'] = 'wooden_rod', ['label'] = 'Wooden Rod', ['weight'] = 8, ['type'] = 'item', ['image'] = 'wooden_rod.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'The starter rod. One slot.', ['client'] = { export = 'qs-fishingjob.toggleFishingRod' } },
['carbon_rod'] = { ['name'] = 'carbon_rod', ['label'] = 'Carbon Rod', ['weight'] = 7, ['type'] = 'item', ['image'] = 'carbon_rod.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Two slots, and a little more from everything fitted.', ['client'] = { export = 'qs-fishingjob.toggleFishingRod' } },
['composite_rod'] = { ['name'] = 'composite_rod', ['label'] = 'Composite Rod', ['weight'] = 7, ['type'] = 'item', ['image'] = 'composite_rod.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Three slots, and a third more from everything fitted.', ['client'] = { export = 'qs-fishingjob.toggleFishingRod' } },
['tournament_rod'] = { ['name'] = 'tournament_rod', ['label'] = 'Tournament Rod', ['weight'] = 6, ['type'] = 'item', ['image'] = 'tournament_rod.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'All four slots. Lands bigger fish, and breaks more often.', ['client'] = { export = 'qs-fishingjob.toggleFishingRod' } },
['master_rod'] = { ['name'] = 'master_rod', ['label'] = 'Master Rod', ['weight'] = 6, ['type'] = 'item', ['image'] = 'master_rod.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Double from everything fitted. Snaps far more easily.', ['client'] = { export = 'qs-fishingjob.toggleFishingRod' } },

-- Fishing kit — opens the panel where rod attachments are fitted

['fishing_kit'] = { ['name'] = 'fishing_kit', ['label'] = 'Fishing Kit', ['weight'] = 8, ['type'] = 'item', ['image'] = 'fishing_kit.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Open it to fit gear to your rod.', ['client'] = { export = 'qs-fishingjob.toggleFishingKit' } },

-- Attachments — fitted from the fishing kit, never used directly

['barbed_hook'] = { ['name'] = 'barbed_hook', ['label'] = 'Barbed Hook', ['weight'] = 100, ['type'] = 'item', ['image'] = 'barbed_hook.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Hook. Fitted from the fishing kit.' },
['float_bobber'] = { ['name'] = 'float_bobber', ['label'] = 'Float Bobber', ['weight'] = 100, ['type'] = 'item', ['image'] = 'float_bobber.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Hook. Fitted from the fishing kit.' },
['circle_hook'] = { ['name'] = 'circle_hook', ['label'] = 'Circle Hook', ['weight'] = 100, ['type'] = 'item', ['image'] = 'circle_hook.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Hook. Fitted from the fishing kit.' },

['spinning_reel'] = { ['name'] = 'spinning_reel', ['label'] = 'Spinning Reel', ['weight'] = 200, ['type'] = 'item', ['image'] = 'spinning_reel.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Reel. Fitted from the fishing kit.' },
['monofilament_reel'] = { ['name'] = 'monofilament_reel', ['label'] = 'Monofilament Reel', ['weight'] = 200, ['type'] = 'item', ['image'] = 'monofilament_reel.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Reel. Fitted from the fishing kit.' },
['graphite_reel'] = { ['name'] = 'graphite_reel', ['label'] = 'Graphite Reel', ['weight'] = 200, ['type'] = 'item', ['image'] = 'graphite_reel.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Reel. Reaches deeper water.' },
['deepsea_reel'] = { ['name'] = 'deepsea_reel', ['label'] = 'Deep Sea Reel', ['weight'] = 260, ['type'] = 'item', ['image'] = 'deepsea_reel.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Reel. Reaches the deepest water.' },

['braided_line'] = { ['name'] = 'braided_line', ['label'] = 'Braided Line', ['weight'] = 150, ['type'] = 'item', ['image'] = 'braided_line.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Line. Fitted from the fishing kit.' },
['fluorocarbon_line'] = { ['name'] = 'fluorocarbon_line', ['label'] = 'Fluorocarbon Line', ['weight'] = 150, ['type'] = 'item', ['image'] = 'fluorocarbon_line.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Line. Fitted from the fishing kit.' },
['steel_leader'] = { ['name'] = 'steel_leader', ['label'] = 'Steel Leader', ['weight'] = 160, ['type'] = 'item', ['image'] = 'steel_leader.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Line. Holds against a hard fight, and reaches deeper.' },

-- Bait — optional, makes the fish that favour it far likelier to bite

['earthworms'] = { ['name'] = 'earthworms', ['label'] = 'Earthworms', ['weight'] = 1, ['type'] = 'item', ['image'] = 'earthworms.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Bait.' },
['crickets'] = { ['name'] = 'crickets', ['label'] = 'Crickets', ['weight'] = 1, ['type'] = 'item', ['image'] = 'crickets.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Bait.' },
['grasshopper'] = { ['name'] = 'grasshopper', ['label'] = 'Grasshopper', ['weight'] = 1, ['type'] = 'item', ['image'] = 'grasshopper.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Bait.' },
['leech'] = { ['name'] = 'leech', ['label'] = 'Leech', ['weight'] = 1, ['type'] = 'item', ['image'] = 'leech.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Bait.' },
['shrimp'] = { ['name'] = 'shrimp', ['label'] = 'Shrimp', ['weight'] = 1, ['type'] = 'item', ['image'] = 'shrimp.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Bait.' },
['minnow'] = { ['name'] = 'minnow', ['label'] = 'Minnow', ['weight'] = 1, ['type'] = 'item', ['image'] = 'minnow.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Bait.' },
['crab'] = { ['name'] = 'crab', ['label'] = 'Crab', ['weight'] = 1, ['type'] = 'item', ['image'] = 'crab.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Bait. Also what a crab trap is for.' },
['anguile'] = { ['name'] = 'anguile', ['label'] = 'Anguile', ['weight'] = 1, ['type'] = 'item', ['image'] = 'anguile.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Bait.' },
['squid'] = { ['name'] = 'squid', ['label'] = 'Squid', ['weight'] = 1, ['type'] = 'item', ['image'] = 'squid.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Bait.' },

-- Fish: shallow water

['sardine'] = { ['name'] = 'sardine', ['label'] = 'Sardine', ['weight'] = 100, ['type'] = 'item', ['image'] = 'sardine.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Shallow water. Very common.' },
['roach'] = { ['name'] = 'roach', ['label'] = 'Roach', ['weight'] = 200, ['type'] = 'item', ['image'] = 'roach.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Shallow water. Very common.' },
['jacksmelt'] = { ['name'] = 'jacksmelt', ['label'] = 'Jacksmelt', ['weight'] = 250, ['type'] = 'item', ['image'] = 'jacksmelt.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Shallow water.' },
['yellow_perch'] = { ['name'] = 'yellow_perch', ['label'] = 'Yellow Perch', ['weight'] = 300, ['type'] = 'item', ['image'] = 'yellow_perch.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Shallow water.' },
['surfperch'] = { ['name'] = 'surfperch', ['label'] = 'Surfperch', ['weight'] = 350, ['type'] = 'item', ['image'] = 'surfperch.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Shallow water.' },

-- Fish: mid-water

['mackerel'] = { ['name'] = 'mackerel', ['label'] = 'Mackerel', ['weight'] = 500, ['type'] = 'item', ['image'] = 'mackerel.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Mid-water.' },
['calico_bass'] = { ['name'] = 'calico_bass', ['label'] = 'Calico Bass', ['weight'] = 700, ['type'] = 'item', ['image'] = 'calico_bass.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Mid-water.' },
['corbina'] = { ['name'] = 'corbina', ['label'] = 'California Corbina', ['weight'] = 600, ['type'] = 'item', ['image'] = 'corbina.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Mid-water.' },
['rockfish'] = { ['name'] = 'rockfish', ['label'] = 'Rockfish', ['weight'] = 900, ['type'] = 'item', ['image'] = 'rockfish.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Mid-water.' },
['eel'] = { ['name'] = 'eel', ['label'] = 'Eel', ['weight'] = 800, ['type'] = 'item', ['image'] = 'eel.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Mid-water.' },
['pike'] = { ['name'] = 'pike', ['label'] = 'Pike', ['weight'] = 2500, ['type'] = 'item', ['image'] = 'pike.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Mid-water.' },
['catfish'] = { ['name'] = 'catfish', ['label'] = 'Catfish', ['weight'] = 3000, ['type'] = 'item', ['image'] = 'catfish.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Mid-water.' },
['sheephead'] = { ['name'] = 'sheephead', ['label'] = 'Sheephead', ['weight'] = 1800, ['type'] = 'item', ['image'] = 'sheephead.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Mid-water.' },

-- Fish: deep water

['salmon'] = { ['name'] = 'salmon', ['label'] = 'Salmon', ['weight'] = 3000, ['type'] = 'item', ['image'] = 'salmon.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Deep water.' },
['lingcod'] = { ['name'] = 'lingcod', ['label'] = 'Lingcod', ['weight'] = 3000, ['type'] = 'item', ['image'] = 'lingcod.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Deep water.' },
['barracuda'] = { ['name'] = 'barracuda', ['label'] = 'Barracuda', ['weight'] = 2800, ['type'] = 'item', ['image'] = 'barracuda.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Deep water.' },
['california_halibut'] = { ['name'] = 'california_halibut', ['label'] = 'California Halibut', ['weight'] = 3500, ['type'] = 'item', ['image'] = 'california_halibut.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Deep water.' },
['yellowtail'] = { ['name'] = 'yellowtail', ['label'] = 'Yellowtail', ['weight'] = 4500, ['type'] = 'item', ['image'] = 'yellowtail.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Deep water.' },
['tuna'] = { ['name'] = 'tuna', ['label'] = 'Tuna', ['weight'] = 6000, ['type'] = 'item', ['image'] = 'tuna.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Deep water. Valuable.' },
['white_seabass'] = { ['name'] = 'white_seabass', ['label'] = 'White Seabass', ['weight'] = 5000, ['type'] = 'item', ['image'] = 'white_seabass.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Deep water. Valuable.' },

-- Fish: abyssal

['horn_shark'] = { ['name'] = 'horn_shark', ['label'] = 'Horn Shark', ['weight'] = 8000, ['type'] = 'item', ['image'] = 'horn_shark.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Abyssal water. A trophy fish.' },
['pacific_halibut'] = { ['name'] = 'pacific_halibut', ['label'] = 'Pacific Halibut', ['weight'] = 11000, ['type'] = 'item', ['image'] = 'pacific_halibut.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Abyssal water. A trophy fish.' },
['stingray'] = { ['name'] = 'stingray', ['label'] = 'Stingray', ['weight'] = 10000, ['type'] = 'item', ['image'] = 'stingray.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Abyssal water. Never in pairs.' },
['swordfish'] = { ['name'] = 'swordfish', ['label'] = 'Swordfish', ['weight'] = 14000, ['type'] = 'item', ['image'] = 'swordfish.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Abyssal water. The big one.' },

-- Junk — what a bad cast brings up. Still sells.

['boot'] = { ['name'] = 'boot', ['label'] = 'Old Boot', ['weight'] = 700, ['type'] = 'item', ['image'] = 'boot.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Somebody lost this. You found it.' },

-- Crab traps — must stay useable: using one over deep water drops it

['crab_trap'] = { ['name'] = 'crab_trap', ['label'] = 'Crab Trap', ['weight'] = 4000, ['type'] = 'item', ['image'] = 'crab_trap.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Drop it in deep water and come back later.', ['client'] = { export = 'qs-fishingjob.useCrabTrap' } },

-- Crab — what a trap brings up (the `crab` bait above comes from here too)

['brown_crab'] = { ['name'] = 'brown_crab', ['label'] = 'Brown Crab', ['weight'] = 600, ['type'] = 'item', ['image'] = 'brown_crab.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Trapped on the sea bed.' },
['striped_red_crab'] = { ['name'] = 'striped_red_crab', ['label'] = 'Striped Red Crab', ['weight'] = 1000, ['type'] = 'item', ['image'] = 'striped_red_crab.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'Deep water. Worth having.' },
['yellow_crab'] = { ['name'] = 'yellow_crab', ['label'] = 'Yellow Crab', ['weight'] = 1600, ['type'] = 'item', ['image'] = 'yellow_crab.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'The one you set traps hoping for.' },

-- Trawl nets — useable from the helm of a rented boat

['drift_net'] = { ['name'] = 'drift_net', ['label'] = 'Drift Net', ['weight'] = 6000, ['type'] = 'item', ['image'] = 'drift_net.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'The starter trawl. Forty fish before it has to come up.', ['client'] = { export = 'qs-fishingjob.useDriftNet' } },
['trawl_net'] = { ['name'] = 'trawl_net', ['label'] = 'Trawl Net', ['weight'] = 9000, ['type'] = 'item', ['image'] = 'trawl_net.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Ninety fish. A long run between hauls.', ['client'] = { export = 'qs-fishingjob.useTrawlNet' } },
['deepsea_net'] = { ['name'] = 'deepsea_net', ['label'] = 'Deep Sea Net', ['weight'] = 14000, ['type'] = 'item', ['image'] = 'deepsea_net.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'A hundred and eighty. The net a working boat carries.', ['client'] = { export = 'qs-fishingjob.useDeepSeaNet' } },

-- Spearfishing
['speargun'] = { ['name'] = 'speargun', ['label'] = 'Speargun', ['weight'] = 4000, ['type'] = 'item', ['image'] = 'speargun.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Only works underwater. Only takes sharks.', ['client'] = { export = 'qs-fishingjob.useSpeargun' } },
['spear'] = { ['name'] = 'spear', ['label'] = 'Spear', ['weight'] = 300, ['type'] = 'item', ['image'] = 'spear.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'One shot. Miss and you swim down for it.' },
['dive_tank'] = { ['name'] = 'dive_tank', ['label'] = 'Dive Tank', ['weight'] = 1000, ['type'] = 'item', ['image'] = 'dive_tank.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Air. Buys you comfort, not access.', ['client'] = { export = 'qs-fishingjob.useDiveTank' } },
['shark'] = { ['name'] = 'shark', ['label'] = 'Shark', ['weight'] = 20000, ['type'] = 'item', ['image'] = 'shark.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'No rod ever landed one of these.' },
['brochette_fish_raw'] = { ['name'] = 'brochette_fish_raw', ['label'] = 'Raw Fish Skewer', ['weight'] = 300, ['type'] = 'item', ['image'] = 'brochette_fish_raw.png', ['unique'] = false, ['useable'] = false, ['shouldClose'] = false, ['combinable'] = nil, ['description'] = 'A fish threaded onto a stick. It needs a fire.' },
['brochette_fish_cooked'] = { ['name'] = 'brochette_fish_cooked', ['label'] = 'Cooked Fish Skewer', ['weight'] = 280, ['type'] = 'item', ['image'] = 'brochette_fish_cooked.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Turned over the flames until it was exactly right.', ['client'] = { status = { hunger = 250000 }, usetime = 2500, anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger_fp' }, prop = { model = 'prop_cs_burger_01', pos = vec3(0.02, 0.02, -0.02), rot = vec3(0.0, 0.0, 0.0) }, disable = { move = false, car = true, combat = true } } },
['brochette_fish_burn'] = { ['name'] = 'brochette_fish_burn', ['label'] = 'Burnt Fish Skewer', ['weight'] = 260, ['type'] = 'item', ['image'] = 'brochette_fish_burn.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'Left in the fire too long. Still food, technically.', ['client'] = { status = { hunger = 60000 }, usetime = 2500, anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger_fp' }, prop = { model = 'prop_cs_burger_01', pos = vec3(0.02, 0.02, -0.02), rot = vec3(0.0, 0.0, 0.0) }, disable = { move = false, car = true, combat = true } } },

-- Espeto boat — not consumed; packing up hands the item straight back

['skewer_grill_boat'] = { ['name'] = 'skewer_grill_boat', ['label'] = 'Skewer Grill Boat', ['weight'] = 12000, ['type'] = 'item', ['image'] = 'skewer_boat.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'A sardine grill on a beached boat. Set it down on dry land.', ['client'] = { export = 'qs-fishingjob.useFoodBoat' } },

-- Campfire fuel — these belong to qs-lumberjack. Skip them if you run it.
['oak_wood'] = { ['name'] = 'oak_wood', ['label'] = 'Oak wood', ['weight'] = 250, ['type'] = 'item', ['image'] = 'oak_wood.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'A dense and durable oak wood log.', ['client'] = { export = 'qs-fishingjob.lightCampfire' } },
['pine_wood'] = { ['name'] = 'pine_wood', ['label'] = 'Pine wood', ['weight'] = 250, ['type'] = 'item', ['image'] = 'pine_wood.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'A strong piece of pine wood.', ['client'] = { export = 'qs-fishingjob.lightCampfire' } },
['maple_wood'] = { ['name'] = 'maple_wood', ['label'] = 'Maple wood', ['weight'] = 250, ['type'] = 'item', ['image'] = 'maple_wood.png', ['unique'] = false, ['useable'] = true, ['shouldClose'] = true, ['combinable'] = nil, ['description'] = 'A smooth and solid maple wood log.', ['client'] = { export = 'qs-fishingjob.lightCampfire' } },

}
--WKLeaksuTOn8rTopUB : https://discord.gg/zqcBffbMZn
--WKLeaksofOnjmTopSw : https://discord.gg/zqcBffbMZn
--WKLeaks3EOnZBTopQc : https://discord.gg/zqcBffbMZn
--WKLeak-IEOn1sTopdi : https://discord.gg/zqcBffbMZn
--WKLeakswHOnYDTopAm : https://discord.gg/zqcBffbMZn
