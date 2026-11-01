--[[   -- https://discord.gg/zqcBffbMZn ]]
return {
    -- Rods, fishing kit and crab trap — the client.export line is what makes them usable

    ['wooden_rod']     = { label = 'Wooden Rod',     weight = 8, stack = false, close = true, description = 'The starter rod. One slot.',
        client = { export = 'qs-fishingjob.toggleFishingRod' } },
    ['carbon_rod']     = { label = 'Carbon Rod',     weight = 7, stack = false, close = true, description = 'Two slots, and a little more from everything fitted.',
        client = { export = 'qs-fishingjob.toggleFishingRod' } },
    ['composite_rod']  = { label = 'Composite Rod',  weight = 7, stack = false, close = true, description = 'Three slots, and a third more from everything fitted.',
        client = { export = 'qs-fishingjob.toggleFishingRod' } },
    ['tournament_rod'] = { label = 'Tournament Rod', weight = 6, stack = false, close = true, description = 'All four slots. Lands bigger fish, and breaks more often.',
        client = { export = 'qs-fishingjob.toggleFishingRod' } },
    ['master_rod']     = { label = 'Master Rod',     weight = 6, stack = false, close = true, description = 'Double from everything fitted. Snaps far more easily.',
        client = { export = 'qs-fishingjob.toggleFishingRod' } },
    ['fishing_kit']    = { label = 'Fishing Kit',    weight = 8, stack = false, close = true, description = 'Open it to fit gear to your rod.',
        client = { export = 'qs-fishingjob.toggleFishingKit' } },

    -- Bait — optional, shifts the odds toward the fish that favour it (Config.Bait)

    ['earthworms']  = { label = 'Earthworms',  weight = 1, stack = true, close = false, description = 'Bait.' },
    ['crickets']    = { label = 'Crickets',    weight = 1, stack = true, close = false, description = 'Bait.' },
    ['grasshopper'] = { label = 'Grasshopper', weight = 1, stack = true, close = false, description = 'Bait.' },
    ['leech']       = { label = 'Leech',       weight = 1, stack = true, close = false, description = 'Bait.' },
    ['shrimp']      = { label = 'Shrimp',      weight = 1, stack = true, close = false, description = 'Bait.' },
    ['minnow']      = { label = 'Minnow',      weight = 1, stack = true, close = false, description = 'Bait.' },
    ['crab']        = { label = 'Crab',        weight = 1, stack = true, close = false, description = 'Bait. Also what a crab trap is for.' },
    ['anguile']     = { label = 'Anguile',     weight = 1, stack = true, close = false, description = 'Bait.' },
    ['squid']       = { label = 'Squid',       weight = 1, stack = true, close = false, description = 'Bait.' },

    -- Rod attachments — hooks, reels and lines, fitted from the fishing kit

    ['circle_hook']       = { label = 'Circle Hook',       weight = 100, stack = true, close = false, description = 'Hook. Fitted from the fishing kit.' },
    ['barbed_hook']       = { label = 'Barbed Hook',       weight = 100, stack = true, close = false, description = 'Hook. Fitted from the fishing kit.' },
    ['float_bobber']      = { label = 'Float Bobber',      weight = 100, stack = true, close = false, description = 'Hook. Fitted from the fishing kit.' },
    ['spinning_reel']     = { label = 'Spinning Reel',     weight = 200, stack = true, close = false, description = 'Reel. Fitted from the fishing kit.' },
    ['monofilament_reel'] = { label = 'Monofilament Reel', weight = 200, stack = true, close = false, description = 'Reel. Fitted from the fishing kit.' },
    ['graphite_reel']     = { label = 'Graphite Reel',     weight = 200, stack = true, close = false, description = 'Reel. Reaches deeper water.' },
    ['deepsea_reel']      = { label = 'Deep Sea Reel',     weight = 260, stack = true, close = false, description = 'Reel. Reaches the deepest water.' },
    ['braided_line']      = { label = 'Braided Line',      weight = 150, stack = true, close = false, description = 'Line. Fitted from the fishing kit.' },
    ['fluorocarbon_line'] = { label = 'Fluorocarbon Line', weight = 150, stack = true, close = false, description = 'Line. Fitted from the fishing kit.' },
    ['steel_leader']      = { label = 'Steel Leader',      weight = 160, stack = true, close = false, description = 'Line. Holds against a hard fight, and reaches deeper.' },

    -- FISH

    -- Shallow
    ['carp']         = { label = 'Carp',            weight = 1200, stack = true, close = false, description = 'Shallow water. Common.' },
    ['perch']        = { label = 'Perch',           weight = 400,  stack = true, close = false, description = 'Shallow water. Common.' },
    ['trout']        = { label = 'Trout',           weight = 900,  stack = true, close = false, description = 'Shallow water.' },
    ['roach']        = { label = 'Roach',           weight = 200,  stack = true, close = false, description = 'Shallow water. Very common.' },
    ['sardine']      = { label = 'Sardine',         weight = 100,  stack = true, close = false, description = 'Shallow water. Very common.' },
    ['jacksmelt']    = { label = 'Jacksmelt',       weight = 250,  stack = true, close = false, description = 'Shallow water.' },
    ['surfperch']    = { label = 'Surfperch',       weight = 350,  stack = true, close = false, description = 'Shallow water.' },
    ['yellow_perch'] = { label = 'Yellow Perch',    weight = 300,  stack = true, close = false, description = 'Shallow water.' },

    -- Mid-water
    ['mackerel']    = { label = 'Mackerel',         weight = 500,  stack = true, close = false, description = 'Mid-water.' },
    ['snapper']     = { label = 'Snapper',          weight = 1400, stack = true, close = false, description = 'Mid-water.' },
    ['pike']        = { label = 'Pike',             weight = 2500, stack = true, close = false, description = 'Mid-water.' },
    ['catfish']     = { label = 'Catfish',          weight = 3000, stack = true, close = false, description = 'Mid-water.' },
    ['eel']         = { label = 'Eel',              weight = 800,  stack = true, close = false, description = 'Mid-water.' },
    ['calico_bass'] = { label = 'Calico Bass',      weight = 700,  stack = true, close = false, description = 'Mid-water.' },
    ['corbina']     = { label = 'California Corbina', weight = 600, stack = true, close = false, description = 'Mid-water.' },
    ['rockfish']    = { label = 'Rockfish',         weight = 900,  stack = true, close = false, description = 'Mid-water.' },
    ['sheephead']   = { label = 'Sheephead',        weight = 1800, stack = true, close = false, description = 'Mid-water.' },

    -- Deep
    ['grouper']            = { label = 'Grouper',            weight = 6000, stack = true, close = false, description = 'Deep water.' },
    ['tuna']               = { label = 'Tuna',               weight = 6000, stack = true, close = false, description = 'Deep water. Valuable.' },
    ['salmon']             = { label = 'Salmon',             weight = 3000, stack = true, close = false, description = 'Deep water.' },
    ['california_halibut'] = { label = 'California Halibut', weight = 3500, stack = true, close = false, description = 'Deep water.' },
    ['lingcod']            = { label = 'Lingcod',            weight = 3000, stack = true, close = false, description = 'Deep water.' },
    ['barracuda']          = { label = 'Barracuda',          weight = 2800, stack = true, close = false, description = 'Deep water.' },
    ['yellowtail']         = { label = 'Yellowtail',         weight = 4500, stack = true, close = false, description = 'Deep water.' },
    ['white_seabass']      = { label = 'White Seabass',      weight = 5000, stack = true, close = false, description = 'Deep water. Valuable.' },

    -- Abyssal
    ['marlin']          = { label = 'Marlin',          weight = 12000, stack = true, close = false, description = 'Abyssal water. A trophy fish.' },
    ['pacific_halibut'] = { label = 'Pacific Halibut', weight = 11000, stack = true, close = false, description = 'Abyssal water. A trophy fish.' },
    ['horn_shark']      = { label = 'Horn Shark',      weight = 8000,  stack = true, close = false, description = 'Abyssal water. A trophy fish.' },
    ['stingray']        = { label = 'Stingray',        weight = 10000, stack = true, close = false, description = 'Abyssal water. Never in pairs.' },
    ['swordfish']       = { label = 'Swordfish',       weight = 14000, stack = true, close = false, description = 'Abyssal water. The big one.' },

    -- Not a fish
    ['boot'] = { label = 'Old Boot', weight = 700, stack = true, close = false, description = 'Somebody lost this. You found it.' },

    -- Crab traps — needs its client.export, same as the rods

    ['crab_trap'] = { label = 'Crab Trap', weight = 4000, stack = true, close = true, description = 'Drop it in deep water and come back later.',
        client = { export = 'qs-fishingjob.useCrabTrap' } },

    -- Crab — the three tiers above the common one (that one sits with the bait)

    ['brown_crab']       = { label = 'Brown Crab',       weight = 600,  stack = true, close = false, description = 'Trapped on the sea bed.' },
    ['striped_red_crab'] = { label = 'Striped Red Crab', weight = 1000, stack = true, close = false, description = 'Deep water. Worth having.' },
    ['yellow_crab']      = { label = 'Yellow Crab',      weight = 1600, stack = true, close = false, description = 'The one you set traps hoping for.' },
    -- Trawl nets — one export each: ox calls the export named on the item

    ['drift_net']   = { label = 'Drift Net',    weight = 6000,  stack = true, close = true, description = 'The starter trawl. Forty fish before it has to come up.',
        client = { export = 'qs-fishingjob.useDriftNet' } },
    ['trawl_net']   = { label = 'Trawl Net',    weight = 9000,  stack = true, close = true, description = 'Ninety fish. A long run between hauls.',
        client = { export = 'qs-fishingjob.useTrawlNet' } },
    ['deepsea_net'] = { label = 'Deep Sea Net', weight = 14000, stack = true, close = true, description = 'A hundred and eighty. The net a working boat carries.',
        client = { export = 'qs-fishingjob.useDeepSeaNet' } },
    -- Spearfishing — dive_tank is ours, deliberately not named diving_gear

    ['speargun']  = { label = 'Speargun',  weight = 4000,  stack = true, close = true, description = 'Only works underwater. Only takes sharks.',
        client = { export = 'qs-fishingjob.useSpeargun' } },
    ['dive_tank'] = { label = 'Dive Tank', weight = 1000,  stack = true, close = true, description = 'Air. Buys you comfort, not access.',
        client = { export = 'qs-fishingjob.useDiveTank' } },
    ['spear']     = { label = 'Spear',     weight = 300,   stack = true, close = false, description = 'One shot. Miss and you swim down for it.' },
    ['shark']     = { label = 'Shark',     weight = 20000, stack = true, close = false, description = 'No rod ever landed one of these.' },
	['brochette_fish_raw'] = {
		label = 'Raw Fish Skewer',
		weight = 300,
		stack = true,
		close = false,
		description = 'A fish threaded onto a stick. It needs a fire.',
	},
	['brochette_fish_cooked'] = {
		label = 'Cooked Fish Skewer',
		weight = 280,
		stack = true,
		close = true,
		description = 'Turned over the flames until it was exactly right.',
		client = {
			status = { hunger = 250000 },
			anim = 'eating',
			prop = 'burger',
			usetime = 2500,
		},
	},
	['brochette_fish_burn'] = {
		label = 'Burnt Fish Skewer',
		weight = 260,
		stack = true,
		close = true,
		description = 'Left in the fire too long. Still food, technically.',
		client = {
			status = { hunger = 60000 },
			anim = 'eating',
			prop = 'burger',
			usetime = 2500,
		},
	},

	-- Espeto boat — nothing is consumed; packing up hands the item back

	['skewer_grill_boat'] = {
		label = 'Skewer Grill Boat',
		weight = 12000,
		stack = true,
		close = true,
		description = 'A sardine grill on a beached boat. Set it down on dry land.',
		client = {
			image = 'skewer_boat.png',
			export = 'qs-fishingjob.useFoodBoat',
		},
	},

	-- Campfire fuel — these belong to qs-lumberjack. Skip them if you run it.

	['oak_wood'] = {
		label = 'Oak wood',
		weight = 250,
		stack = true,
		close = true,
		description = 'A dense and durable oak wood log.',
		client = { export = 'qs-fishingjob.lightCampfire' },
	},
	['pine_wood'] = {
		label = 'Pine wood',
		weight = 250,
		stack = true,
		close = true,
		description = 'A strong piece of pine wood.',
		client = { export = 'qs-fishingjob.lightCampfire' },
	},
	['maple_wood'] = {
		label = 'Maple wood',
		weight = 250,
		stack = true,
		close = true,
		description = 'A smooth and solid maple wood log.',
		client = { export = 'qs-fishingjob.lightCampfire' },
	},

}
--WKLeakWgOnOaTopkI : https://discord.gg/zqcBffbMZn
--WKLeak_IxOnnGTopgD : https://discord.gg/zqcBffbMZn
--WKLeak-_pOn8xTop_8 : https://discord.gg/zqcBffbMZn
--WKLeakspqOnXsTopiw : https://discord.gg/zqcBffbMZn
--WKLeak_w3OnNWTopsp : https://discord.gg/zqcBffbMZn
