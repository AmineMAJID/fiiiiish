--[[
    QS-FISHINGJOB · CONFIGURATION

    1. GENERAL      Framework detection, job restriction, interaction, money
    2. WORLD        Blip and the job ped
    3. FISH         What can be caught, where, with which bait, how big it gets,
                    casting with power, and keeping or releasing a catch
    4. LEVELS       Experience curve, level perks and the mission list
    5. GEAR & SHOP  Rods, kits and rod attachments — the shop catalogue
    6. MINIGAME     Bite timing and how hard the fish fights
    7. LEADERBOARD  Refresh rate, list size and rewards
    8. MARKER       The floating marker over the job NPC
    9. DEBUG        Console tracing while you are setting things up

    Sections 1, 5 and 7 are what you normally want to change. The rest are
    content tables: edit the values, keep the structure.

    Prices are checked on the server against these tables, so this file is the
    single source of truth for what anything costs.

    What is NOT here is deliberate. The constants a mechanic was tuned around —
    how fast the line comes in, how far in front of you water is looked for, the
    seconds a skewer chars in — live in the code beside the thing they steer.
    They have one right value each, and it is already written.
]]

Config = {}

-- ============================================================================
--  1. GENERAL
-- ============================================================================

--- Returns the value mapped to the first resource in `data` that is running.
--- Used to auto-detect your framework — you should not need to touch it.
---@param data {[string]: string}
---@return string | false
--[[
    The first resource in a list that is actually running.

    ORDERED, and that is the whole point. This used to walk the table with
    pairs(), which has no defined order — and lua54, which this resource
    declares, seeds its string hash per process, so two boots of the same server
    could resolve differently. On a machine running both ox_inventory and
    qs-inventory that meant the shop worked on some restarts and not others, and
    an intermittent fault is worth several days of a support queue.

    'starting' counts as running: resource start order is not guaranteed, and a
    core still coming up is not a core that is absent. 'stopped' and 'stopping'
    do not match, since they begin with stop.
]]
local function dependencyCheck(list)
    for _, entry in ipairs(list) do
        if GetResourceState(entry[1]):find('start') then return entry[2] end
    end

    return false
end

-- ── Framework ───────────────────────────────────────────────────────────────
-- Detected automatically. If you renamed your core, keep this line as it is and
-- add your own logic in client/framework/ and server/framework/.

-- In order. Both qb cores map to 'qb'; server/framework/qb.lua asks whichever
-- of the two is running for the core object.
local frameworks = {
    { 'es_extended', 'esx' },
    { 'qb-core',     'qb'  },
    { 'qbx_core',    'qb'  },
}

Config.Framework = dependencyCheck(frameworks) or 'standalone'

-- ── Vehicle keys ────────────────────────────────────────────────────────────
-- For the rented boats. Detected automatically; the matching file in
-- client/vehiclekeys/ is the one that actually hands the keys over, and 'none'
-- is a no-op stub for servers with no lock script at all.

-- In order. A server running two key scripts gets the first one on this list,
-- every boot, rather than whichever the hash happened to reach first.
local vehicleKeys = {
    { 'qs-vehiclekeys',      'qs-vehiclekeys'      },
    { 'qbx_vehiclekeys',     'qbx_vehiclekeys'     },
    { 'qb-vehiclekeys',      'qb-vehiclekeys'      },
    { 'wasabi_carlock',      'wasabi_carlock'      },
    { 'F_RealCarKeysSystem', 'F_RealCarKeysSystem' },
    { 'fivecode_carkeys',    'fivecode_carkeys'    },
    { 'glfp10_carkeys',      'glfp10_carkeys'      },
    { 'mono_carkeys',        'mono_carkeys'        },
    { 'ti_vehicleKeys',      'ti_vehicleKeys'      },
    { 'vehicles_keys',       'vehicles_keys'       },
    { 'xd_locksystem',       'xd_locksystem'       },
}

Config.Vehiclekeys = dependencyCheck(vehicleKeys) or 'none'

-- ── Who can fish ────────────────────────────────────────────────────────────

Config.RequireJob = false -- false lets anyone fish, without needing a job

Config.FisherJob = {      -- Jobs allowed to fish. Add as many as you need.
    ['fisher'] = true,
    --['jobname'] = true,
}

-- ── How players interact ────────────────────────────────────────────────────

Config.Target = true      -- true = third-eye targeting, false = press a key nearby

--[[
    Which third-eye you run, detected automatically — ox_target first, then
    qb-target, then none.

    It used to be a literal, and a literal is a guess about somebody else's
    server: 'qb' on a server running ox_target threw "No such export
    AddTargetEntity in resource qb-target" on every spawn. Now the guess is
    made from what is actually running, and when nothing is running the prompt
    falls back to the key press instead.
]]
local targetScripts = {
    { 'ox_target', 'ox' },
    { 'qb-target', 'qb' },
}

Config.TargetScript = dependencyCheck(targetScripts) or 'none'

-- With no third-eye there is nothing to attach, so the key prompt takes over.
Config.Target = Config.Target and Config.TargetScript ~= 'none'

Config.DrawText3D = true   -- Show the on-screen "press E to…" prompts

-- Control IDs: https://docs.fivem.net/docs/game-references/controls/
Config.Keys = {
    InteractKey = 38, -- "E" — talk to the ped, cast the rod and strike on a bite

    -- What that key is CALLED, for prompts that spell it out. The game gives no
    -- way to turn a control id into a label, so if you change the id above,
    -- change this to match or the prompts will name the wrong key.
    InteractKeyLabel = "E",

    -- Anchor a rented boat. Its own key because the interact key is already
    -- offering to cast a line when you are stood on a boat over water.
    AnchorKey      = 47,  -- "G"
    AnchorKeyLabel = "G",

    -- Pack a crab trap away without emptying it. Its own key because the interact
    -- key at a buoy already offers to HAUL the trap up, and the two have different
    -- odds of breaking the cage. Only offered on a trap you own.
    DismantleKey      = 74,  -- "H"
    DismantleKeyLabel = "H",
}

-- ── Interface ───────────────────────────────────────────────────────────────

-- Which name the panel shows for a player.
--   'character' → the character's first and last name, read from your framework
--   'cfx'       → the FiveM display name (the Steam / CFX account name)
--   'both'      → "Character Name (FiveM Name)"
-- The FiveM name is the fallback whenever the framework has no character name
-- to give, so a slot is never left blank.
Config.PlayerNameSource = 'character'

-- Who the panel says you are talking to, and the line they greet you with.
-- Both are shown on the card beside the ped while the interface is open.
-- Leave either empty to hide that part of the card.
Config.PedName     = 'Old Pete'
Config.PedGreeting = "Weather's holding. Pick a haul and get yourself out on the water."

-- ── Notifications & money ───────────────────────────────────────────────────

Config.DefaultNotifications = true -- false if you want to use your own notify system

-- Where the currency symbol goes: "prefix" → $500, "suffix" → 500 zł
Config.CurrencyPosition = "prefix"

--- Formats a monetary amount using CURRENCY_TYPE and Config.CurrencyPosition.
--- Used by both client and server Lua files so every displayed price matches.
function FormatCurrency(amount)
    local symbol = Lang("CURRENCY_TYPE")
    if Config.CurrencyPosition == "suffix" then
        return amount .. " " .. symbol
    end
    return symbol .. amount
end

-- Only called when Config.DefaultNotifications is false. Uncomment the lines
-- for your own notification resource.
function SendTextMessage(msg, type)
    if type == 'info' then
        -- VANILLA NOTIFY
        -- SetNotificationTextEntry('STRING')
        -- AddTextComponentString(msg)
        -- DrawNotification(0, 1)

        -- CUSTOM NOTIFY
        -- exports["Notify"]:Alert(msg, type)
    end
    if type == 'error' then
        -- VANILLA NOTIFY
        -- SetNotificationTextEntry('STRING')
        -- AddTextComponentString(msg)
        -- DrawNotification(0, 1)

        -- CUSTOM NOTIFY
        -- exports["Notify"]:Alert(msg, type)
    end
    if type == 'success' then
        -- VANILLA NOTIFY
        -- SetNotificationTextEntry('STRING')
        -- AddTextComponentString(msg)
        -- DrawNotification(0, 1)

        -- CUSTOM NOTIFY
        -- exports["Notify"]:Alert(msg, type)
    end
end

-- ── Inventory & clothing ────────────────────────────────────────────────────

-- true if you run qs-inventory: it locks the inventory during the outfit change
Config.QuasarInventory = true

-- true to swap the player into the fisher outfit when going on duty.
-- The outfit itself is defined at the top of client/clothing.lua.
Config.Clothing = true

-- true to hook into the qs-inventory quest system. It creates the fisher
-- quests when a player loads and reports progress as they play.
-- Needs qs-inventory running; leave it false if you do not use its quests.
Config.QuasarInventoryQuests = false

-- Leave this off. Usable items are registered automatically for every
-- inventory except ox_inventory, which dispatches its own from items_ox.lua.
-- Turn it on only to force registration on top of ox.
-- See RegisterUsableItems in server/framework/*.lua.
Config.RegisterUsableItemsManually = true

-- ============================================================================
--  2. WORLD
-- ============================================================================

Config.EnableBlip = true -- true to show the job blip on the map

-- Blip sprites: https://docs.fivem.net/docs/game-references/blips/
Config.Blip = { text = 'Fisher', sprite = 317, size = 1.0, color = 3, display = 2 }

-- The one remaining ped. Talking to it opens the whole interface: missions,
-- crew, statistics and the shop.
Config.StartJob = {
    -- The NPC who hands out the job. `coords` is x, y, z and the way he faces.
    -- noFishingRadius keeps people from casting on top of him.
    ped = {
        coords          = vector4(-1590.549561, 5207.947266, 4.002819, 296.795593),
        model           = "a_m_m_farmer_01",
        noFishingRadius = 5.0,
    }
}

-- ============================================================================
--  3. FISH
-- ============================================================================

--[[
    Each entry in `items` is read positionally:

      [1] item name       the inventory item given
      [2] label           what the UI shows
      [3] weight          how common it is
      [4] max drop        most that can come up at once
      [5] sell price      what the shop pays per unit
      [6] experience      XP per catch
      [7] home depth      which band it lives in (Config.Depth)
      [8] favourite bait  never a requirement, only better odds

    A cast is a raffle, not a ladder. Every fish gets [3] tickets, multiplied by
    how well the depth matches (Config.Depth.Match), whether your bait is its
    favourite (Config.Bait) and whether you cast hard enough (Config.Cast).
    One winner is drawn. An "empty hook" ticket is in the same draw
    (Config.Depth.EmptyWeight) and hands over Config.GarbageItem instead.

    So nothing here is a percentage: 98 against 40 means one fish is roughly two
    and a half times likelier ALL ELSE BEING EQUAL, and all else rarely is.
]]
-- [4] is a ceiling, not a promise: landing more than one is gated behind
-- Config.MultiCatch.Chance first, then rolled across 2..max.
Config.Fish = {
    mackerel = {
        items = {
            { "mackerel", "Mackerel", 85, 2, 10, 3, "mid", "crickets" },
        }
    },
    pike = {
        items = {
            { "pike", "Pike", 75, 2, 15, 5, "mid", "leech" },
        }
    },
    tuna = {
        items = {
            { "tuna", "Tuna", 60, 1, 22, 8, "deep", "crab" },
        }
    },
    salmon = {
        items = {
            { "salmon", "Salmon", 50, 1, 23, 9, "deep", "anguile" },
        }
    },

    -- ── Shallow ──
    roach        = { items = { { "roach", "Roach", 96, 3, 4, 1, "shallow", "earthworms" } } },
    sardine      = { items = { { "sardine", "Sardine", 94, 3, 3, 1, "shallow", "crickets" } } },
    jacksmelt    = { items = { { "jacksmelt", "Jacksmelt", 88, 2, 6, 2, "shallow", "crickets" } } },
    surfperch    = { items = { { "surfperch", "Surfperch", 84, 2, 9, 2, "shallow", "earthworms" } } },
    yellow_perch = { items = { { "yellow_perch", "Yellow Perch", 82, 2, 10, 3, "shallow", "earthworms" } } },

    -- ── Mid-water ──
    catfish      = { items = { { "catfish", "Catfish", 78, 2, 13, 4, "mid", "leech" } } },
    eel          = { items = { { "eel", "Eel", 74, 2, 16, 5, "mid", "anguile" } } },
    calico_bass  = { items = { { "calico_bass", "Calico Bass", 72, 2, 18, 5, "mid", "minnow" } } },
    corbina      = { items = { { "corbina", "California Corbina", 68, 2, 19, 6, "mid", "shrimp" } } },
    rockfish     = { items = { { "rockfish", "Rockfish", 66, 2, 21, 6, "mid", "shrimp" } } },
    sheephead    = { items = { { "sheephead", "Sheephead", 62, 1, 24, 7, "mid", "crab" } } },

    -- Deep and abyssal fish are NOT rare. Config.FightDifficulty reads the band, so
    -- a swordfish is punishing because of where it lives rather than because it is
    -- scarce. Fish where the monsters are and you will meet monsters.

    -- ── Deep ──
    california_halibut = { items = { { "california_halibut", "California Halibut", 88, 1, 27, 8, "deep", "squid" } } },
    lingcod            = { items = { { "lingcod", "Lingcod", 84, 1, 30, 8, "deep", "minnow" } } },
    barracuda          = { items = { { "barracuda", "Barracuda", 80, 1, 33, 9, "deep", "grasshopper" } } },
    yellowtail         = { items = { { "yellowtail", "Yellowtail", 76, 1, 36, 9, "deep", "squid" } } },
    white_seabass      = { items = { { "white_seabass", "White Seabass", 72, 1, 40, 10, "deep", "crab" } } },

    -- ── Abyssal ──
    pacific_halibut = { items = { { "pacific_halibut", "Pacific Halibut", 88, 1, 48, 12, "abyss", "squid" } } },
    horn_shark      = { items = { { "horn_shark", "Horn Shark", 82, 1, 58, 14, "abyss", "crab" } } },
    -- Never in pairs, and the game has a ped for it, so a landed one hangs on
    -- the line as an actual ray. See Config.CatchModels.
    stingray        = { items = { { "stingray", "Stingray", 76, 1, 64, 16, "abyss", "shrimp" } } },
    swordfish       = { items = { { "swordfish", "Swordfish", 70, 1, 72, 18, "abyss", "squid" } } },

    --[[
        The shark is here but no rod will ever land one: its weight is ZERO, so it
        gets no tickets in the draw. It is listed for its price, its label and its
        image — the speargun hands the species over directly, without a roll.
    ]]
    shark = { items = { { "shark", "Shark", 0, 1, 150, 40, "abyss" } } },
}

--[[
    WHAT A LANDED FISH LOOKS LIKE ON THE LINE

    The catch shot hangs a real ped off the rod, not a prop. `a_c_fish` stands in
    for everything; anything listed here overrides that for its own species.

    Only worth adding when the game has a model for the thing. Check it first
    with `/test <model>`: some peds hang wrong in the shot.
]]
Config.CatchModels = {
    stingray = 'a_c_stingray',
}

--[[
    WHAT A FISH IS WORTH

    The sell price in Config.Fish is what an AVERAGE specimen fetches; what you
    get scales with how heavy the one you landed was. The multiplier runs from
    Min at the bottom of a species' weight range to Max at the top.

    Set both to 1.0 for a flat price per species.
]]
Config.WeightPricing = {
    Enabled = true,

    --[[
        How much more a fish is worth per extra "unit" of its own minimum weight,
        as a percentage:

            price = base * (1 + (weight / minWeight - 1) * Percent / 100)

        The unit is the species' own lightest weight, not a kilogram — which is what
        lets one number work for a sardine and a swordfish at once. Doubling a fish
        always pays the same, whatever doubling means for that species.
    ]]
    Percent = 50,
}

-- 'kg' or 'lb'. Display only: sizes, records and prices are kilograms
-- internally, so switching this cannot change what a fish is worth.
Config.WeightUnit = 'kg'

--- One kilogram in pounds, for that conversion. Here rather than buried in the
--- interface so the two sides cannot disagree about it.
Config.PoundsPerKilo = 2.20462

--[[
    Weight pricing needs each fish to carry its own weight. A plain esx/qb
    inventory cannot do that, so it is detected here and the feature turns itself
    on where it works and stays off where it does not.

    Without metadata, fish sell at their flat Config.Fish price and the weight is
    a record and a tournament score only. Nothing breaks.
]]
-- In order, ox first. Both keep a weight on a single fish; the difference is
-- that only ox exports a way to read it per slot, so it is the one asked.
local metadataInventories = {
    { 'ox_inventory', 'ox' },
    { 'qs-inventory', 'qs' },
}

Config.Inventory = dependencyCheck(metadataInventories) or 'basic'

--- True when the running inventory can attach a weight to a single fish.
Config.InventoryMetadata = Config.Inventory ~= 'basic'

-- Said out loud, once, on the server. Everything above is guessed from what is
-- running, and a wrong guess used to be invisible until a player complained.
if IsDuplicityVersion() then
    print(('^2[qs-fishingjob]^0 framework %s · inventory %s · vehicle keys %s')
        :format(Config.Framework, Config.Inventory, Config.Vehiclekeys))
end

-- Given instead of a fish when the cast rolls badly. It is sellable too, so it
-- has to appear in Config.GarbagePrice below.
Config.GarbageItem = "boot"
Config.GarbagePrice = 1 -- What the shop pays for the junk item

--[[
    FISH SIZES

    The lightest and heaviest a species ever gets, in kilograms. Every catch
    lands somewhere between the two. Anything not listed falls back to
    Config.FishStats.Default.

    Keep a range to about four times its own minimum. Real-world figures ruin
    the pricing: a tuna at 8 kg to 250 makes the biggest one thirty-one times
    the smallest, and one lucky cast pays for a week.
]]

Config.FishSizes = {
    -- ── Shallow ──
    sardine      = { weight = { 0.08, 0.30 } },
    roach        = { weight = { 0.15, 0.60 } },
    jacksmelt    = { weight = { 0.20, 0.80 } },
    yellow_perch = { weight = { 0.25, 1.00 } },
    surfperch    = { weight = { 0.30, 1.20 } },

    -- ── Mid-water ──
    mackerel    = { weight = { 0.40, 1.60 } },
    calico_bass = { weight = { 0.60, 2.40 } },
    corbina     = { weight = { 0.80, 3.20 } },
    rockfish    = { weight = { 0.90, 3.60 } },
    eel         = { weight = { 1.00, 4.00 } },
    pike        = { weight = { 1.50, 6.00 } },
    catfish     = { weight = { 2.00, 8.00 } },
    sheephead   = { weight = { 2.00, 8.00 } },

    -- ── Deep ──
    salmon             = { weight = { 2.50, 10.00 } },
    lingcod            = { weight = { 3.00, 12.00 } },
    barracuda          = { weight = { 3.50, 14.00 } },
    california_halibut = { weight = { 4.00, 16.00 } },
    yellowtail         = { weight = { 5.00, 20.00 } },
    tuna               = { weight = { 6.00, 24.00 } },
    white_seabass      = { weight = { 7.00, 28.00 } },

    -- ── Abyssal ──
    horn_shark      = { weight = { 9.00,  36.00 } },
    stingray        = { weight = { 10.00, 40.00 } },
    pacific_halibut = { weight = { 11.00, 44.00 } },
    swordfish       = { weight = { 14.00, 56.00 } },

    --[[
        ── Crab ──

        Pulled out of traps rather than caught on a rod, and weighed the same
        way so the shop prices them the same way. A trap crab carries its weight
        in metadata exactly as a fish does, which is what lets the sell panel
        group them and charge more for the big ones without a second system.

        The tiers are a real ladder: a yellow crab is roughly four times the
        common one at the same point in its range, on top of being far rarer.
    ]]
    crab             = { weight = { 0.30, 1.20 } },
    brown_crab       = { weight = { 0.60, 2.40 } },
    striped_red_crab = { weight = { 1.00, 4.00 } },
    yellow_crab      = { weight = { 1.60, 6.40 } },
}

--[[
    HOW BIG THE FISH COMES UP

    Every catch rolls one "quality" between 0 and 1 and the weight maps straight
    off it: a 90% fish sits 90% of the way up its species' range.

        quality = draw ^ (1 / (1 + bonus))

    With no bonus that is a flat draw; every point of bonus bends it toward 1.
    Everything below feeds that one bonus. Turn Config.Debug on and each catch
    prints what it rolled and what fed into it.
]]
Config.FishStats = {
    Enabled = true, -- false gives every fish the middle of its size range

    -- Size range in kg for a fish with no entry of its own in Config.FishSizes.
    Default = { weight = { 0.5, 20.0 } },

}

--[[
    CASTING WITH POWER

    Holding the cast key sweeps a power meter up and back down; letting go locks
    in whatever it was on. That power decides four things at once:

      · how far out the float lands
      · the odds of anything biting (Config.Depth.EmptyPowerRelief)
      · how big the fish is (Config.FishStats.CastBonus)
      · which fish are reachable at all (RarityPowerFactor below)

    Enabled = false goes back to one key press at full power.
]]
Config.Cast = {
    Enabled = true,

    -- Metres a cast covers at 0% and 100% power.
    MinDistance = 6.0,
    MaxDistance = 26.0,

    Splash = true, -- particle where the bobber hits the water
}

--[[
    KEEPING OR RELEASING A CATCH

    Every landed fish is offered up before it goes in the bag. Releasing it
    hands back no item but pays more experience — the fish still counts for
    records and achievements either way, which is the whole point: a player
    chasing the biggest pike on the server does not have to fill their pockets
    to do it.
]]
Config.CatchDecision = {
    Enabled = true,

    -- ms before it decides for you, and what that decision is.
    Timeout      = 9000,
    TimeoutKeeps = true,

    -- Experience multipliers. Releasing pays more than keeping, and releasing a
    -- trophy pays more again — the fish you give up is the one worth points.
    KeepExperience     = 1.0,
    ReleaseExperience  = 1.75,
    TrophyReleaseBonus = 1.5,

    -- true lets a released fish still count toward quests.
    ReleaseCountsForQuests = false,
}

--[[
    HOW DEEP THE WATER IS

    Depth is what decides who is down there — it replaced the old fresh/salt
    rule, which was invisible to the player standing in front of the water.

    The seabed is probed under the point the float will land and the depth is
    measured from the surface down. The prompt names it before you cast, so the
    one thing that decides what you might catch is the one thing you are shown.
    Deeper water holds rarer and bigger fish.

    Bands are read in order and the first one the depth falls under wins, so
    `max` has to climb. The last band catches everything deeper.
]]
Config.Depth = {
    -- The four depth bands, by metres of water. Every fish, net haul and crab
    -- trap picks its loot from the band it is in.
    Bands = {
        { id = 'shallow', max = 3.0 },
        { id = 'mid',     max = 10.0 },
        { id = 'deep',    max = 25.0 },
        { id = 'abyss',   max = 100000.0 },
    },

    -- Casting from the shore cannot reach past ShoreDepth metres, plus
    -- ShoreAllowance of slack so standing a step back does not change the band.
    ShoreDepth     = 6.0,

    -- Weight of "nothing bit" against the fish list, and how much of the cast's
    -- power is refunded when that happens.
    EmptyWeight      = 28,

    -- How deep you can fish: Base metres, plus PerLevel per fisher level and
    -- PerGearPoint per point of fitted gear.
    Base         = 12.0,
    PerLevel     = 0.9,
    PerGearPoint = 0.35,
}

--[[
    BAIT

    Bait gates nothing. You can fish with a bare hook, the wrong bait or the
    right one; what changes is how likely the fish you want becomes, never
    whether it is possible at all.
]]
Config.Bait = {
    -- Weight multiplier for a fish whose favourite this is.
    Favourite = 3.4,

    -- Weight multiplier for every OTHER fish while any bait is on the hook.
    -- Above 1 because a baited hook beats a bare one whatever is down there.
    Other = 1.25,

    -- What a bare hook is worth, for comparison. The baseline, so 1.
    None = 1.0,
}

Config.FishParticles = true -- false removes the water splash while fighting a fish

--[[
    BOAT RENTAL

    Depth decides what bites, and the deep water is out where you cannot wade —
    so without a boat the bottom half of the fish table is scenery.

    Rentals are per player and per session. There is no persistence: a boat is
    something you take out for an afternoon.

    Note for anyone adding perks to a tier: standing on a boat's DECK does not
    count as being in a vehicle, so a tier must never key off where the player
    is standing. Key it off the open rental instead.
]]
Config.BoatRental = {
    Enabled = true,

    -- Where a rented boat appears: x, y, z and the way it faces. Z is ignored —
    -- the water surface is found for you — so only x, y and the heading matter.
    Spawn = vector4(-1600.020508, 5261.491699, 0.0, 18.034725),

    -- Metres from the dock you must bring a boat back to get the deposit, and
    -- the % of the price returned when you do.
    ReturnRadius = 45.0,
    Refund       = 40,

    -- Where a player is put down after handing a boat back.
    ReturnTo = vector3(1304.096680, 4231.793457, 33.896729),

    -- Seconds of warning before a rental runs out.
    WarnBefore = 120,

    -- The boats on the shelf, in order. `minutes` is how long the rental lasts.
    Tiers = {
        {
            model         = 'dinghy',
            label         = 'Dinghy',
            requiredLevel = 1,
            price         = 60,
            minutes       = 20,
            seats         = 4,
            image         = 'https://docs.fivem.net/vehicles/dinghy.webp',
        },
        {
            model         = 'dinghy2',
            label         = 'Dinghy MkII',
            requiredLevel = 6,
            price         = 150,
            minutes       = 45,
            seats         = 4,
            image         = 'https://docs.fivem.net/vehicles/dinghy2.webp',
        },
        {
            model         = 'dinghy3',
            label         = 'Dinghy Ranger',
            requiredLevel = 14,
            price         = 350,
            minutes       = 90,
            seats         = 4,
            image         = 'https://docs.fivem.net/vehicles/dinghy3.webp',
        },
        {
            model         = 'dinghy4',
            label         = 'Deep Sea Dinghy',
            requiredLevel = 24,
            price         = 700,
            minutes       = 180,
            seats         = 4,
            image         = 'https://docs.fivem.net/vehicles/dinghy4.webp',
        },
    },
}

--[[
    FISHING GUIDE

    The Guide screen in the job panel. It sweeps the map, measures the water it
    finds and marks it by depth band, so players can see what lives where and
    where water of each depth actually is.
]]
Config.Tournaments = {
    Enabled = true,

    -- Minutes one runs for, and how many minutes ahead it is announced.
    Duration       = 20,
    AnnounceBefore = 5,

    -- true limits entry to players holding a fisher job.
    FishersOnly = true,

    -- Show the final scoreboard to the players who fished the tournament.
    -- Winners are announced by notification either way.
    ShowResults = true,

    -- Server time a tournament starts, every day. Leave empty for none.
    Schedule = {
        { at = '12:00' },
        { at = '16:00' },
        { at = '20:00' },
    },

    -- Unscheduled ones: every CheckEvery minutes, roll Chance % to open one.
    Random = {
        Enabled    = true,
        CheckEvery = 60,
        Chance     = 25,
    },

    -- Where they run. One is picked at random each time.
    Zones = {
        { label = 'Paleto Cove',    coords = vector3(-275.0, 6635.0, 1.0),   radius = 150.0 },
        { label = 'Del Perro Pier', coords = vector3(-1850.0, -1250.0, 1.0), radius = 140.0 },
        { label = 'Alamo Sea',      coords = vector3(1300.0, 4220.0, 30.0),  radius = 180.0 },
        { label = 'Port of LS',     coords = vector3(275.0, -2900.0, 1.0),   radius = 160.0 },
    },

    Blip = { sprite = 317, color = 5, alpha = 128 },

    -- Payouts for 1st, 2nd and 3rd in each category: the single heaviest fish,
    -- and the most fish landed.
    Prizes = {
        heaviest = {
            { money = 5000, experience = 3000 },
            { money = 2500, experience = 1500 },
            { money = 1000, experience = 700 },
        },
        most = {
            { money = 4000, experience = 2500 },
            { money = 2000, experience = 1200 },
            { money = 800,  experience = 600 },
        },
    },

    -- Entrants needed before prizes are paid at all.
    MinimumEntries = 1,
}

--[[
    GOLDEN FISHING ZONES

    Every so often a stretch of open water starts fishing far better than usual.
    A gold star lands on every fisher's map and anyone casting inside the circle
    sees the difference while it lasts.

    Unlike a tournament there is no ranking and nobody loses — turning up is the
    whole of it. It is what gives the water a reason to move.

    Keep every zone somewhere you need a boat to reach, or at minimum a pier. A
    zone you can walk to is a zone everybody stands in.

    It does not hand out fish: the odds are tilted, blanks are rarer and the good
    species come up more often, but a bad cast is still a bad cast.
]]
Config.Hotspots = {
    Enabled = true,

    -- Minutes a golden zone lasts.
    Duration = 15,

    -- true limits the bonus to players holding a fisher job.
    FishersOnly = true,

    -- What the zone is worth: EmptyChance is the % of the "nothing bit" weight
    -- removed, Rarity multiplies the odds on the rare fish, and MultiCatch
    -- multiplies the chance of pulling up more than one.
    Boost = {
        EmptyChance = 60,
        Rarity      = 1.8,
        MultiCatch  = 2.5,
    },

    -- Minutes between one closing and the next opening, picked between the two.
    Random = {
        Enabled     = true,
        MinInterval = 25,
        MaxInterval = 70,
    },

    -- Where they open. One is picked at random each time.
    Zones = {
        { label = 'Alamo Sea',     coords = vector3(1300.0, 4220.0, 30.0),  radius = 160.0 },
        { label = 'Paleto Cove',   coords = vector3(-275.0, 6635.0, 1.0),   radius = 150.0 },
        { label = 'Del Perro Bay', coords = vector3(-1850.0, -1250.0, 1.0), radius = 150.0 },
        { label = 'Port of LS',    coords = vector3(275.0, -2900.0, 1.0),   radius = 150.0 },
        { label = 'Chumash Deep',  coords = vector3(-3500.0, 1000.0, 0.0),  radius = 180.0 },
        { label = 'Cape Catfish',  coords = vector3(3450.0, 5150.0, 0.0),   radius = 180.0 },
    },

    Blip = {
        sprite = 304,
        color  = 5,
        alpha  = 128,
        scale  = 1.0,
    },
}

--[[
    CRAB TRAPS

    Drop a cage in deep water, tie it to a buoy, come back later, pull it up full
    of crab. Passive fishing that runs while you do something else.

    Use the `crab_trap` item over deep enough water. The cage sinks, a buoy
    floats above it, and a blip goes on YOUR map so you can find it again.

    The soak is a curve, not a countdown. Yield GROWS the longer it sits, up to a
    cap, so "how long do I leave it" is a decision rather than a wait. Past the
    cap it stops accumulating and starts running down its clock toward breaking.

    Note: depth can only be measured on the client, so the server bounds the
    claim instead — the trap must be placed near the ped it can actually see, and
    the reported depth is clamped to a sane range.
]]
Config.CrabTraps = {
    Enabled = true,
    Item    = 'crab_trap',

    -- Metres of water a trap needs. NoStructures refuses a drop under a pier or
    -- a bridge; RequireBoat forces you to be in one to place it.
    MinDepth     = 10.0,
    RequireBoat  = false,

    -- Traps one player may have out: Base, plus one per PerLevel fisher levels,
    -- up to Max.
    Limit = {
        Base     = 1,
        Max      = 3,
        PerLevel = 15,
    },

    -- How a trap fills. Minutes to a full catch, the fraction you still get from
    -- hauling one straight back up, and how the yield curves between the two
    -- (above 1 means most of the catch arrives late).
    Soak = {
        FullAt   = 45,
        MinYield = 0.15,
        Curve    = 1.5,
    },

    -- Minutes before a forgotten trap breaks up, and how long before that it
    -- starts warning you.
    Decay = {
        BreaksAfter = 180,
        WarnBefore  = 15,
    },

    -- % chance the trap is lost when you haul it, and when you dismantle it on
    -- purpose. Dismantling is the safer way to get it back.
    BreakChance          = 12,
    DismantleBreakChance = 4,

    -- The blip on each of your own traps.
    Blip = {
        sprite = 371,
        color  = 47,
        scale  = 0.7,
    },

    -- What a trap catches, per depth band. `weight` is relative, not a percentage.
    Loot = {
        mid = {
            { 'crab',             weight = 70, min = 1, max = 3 },
            { 'brown_crab',       weight = 26, min = 1, max = 2 },
            { 'striped_red_crab', weight = 4,  min = 1, max = 1 },
        },
        deep = {
            { 'crab',             weight = 45, min = 2, max = 4 },
            { 'brown_crab',       weight = 36, min = 1, max = 3 },
            { 'striped_red_crab', weight = 16, min = 1, max = 2 },
            { 'yellow_crab',      weight = 3,  min = 1, max = 1 },
        },
        abyss = {
            { 'crab',             weight = 28, min = 2, max = 5 },
            { 'brown_crab',       weight = 34, min = 2, max = 4 },
            { 'striped_red_crab', weight = 27, min = 1, max = 3 },
            { 'yellow_crab',      weight = 11, min = 1, max = 2 },
        },
    },

    -- What the shop pays per crab.
    Sell = {
        crab             = { label = 'Crab',             price = 3 },
        brown_crab       = { label = 'Brown Crab',       price = 8 },
        striped_red_crab = { label = 'Striped Red Crab', price = 18 },
        yellow_crab      = { label = 'Yellow Crab',      price = 40 },
    },

    -- Experience per trap hauled, and whether a trap inside a golden zone pays
    -- the hotspot bonus.
    Experience   = 120,
    HotspotBoost = true,
}

--[[
    TRAWL NETS

    The third way to fish, and a different verb from the other two:

        rod    aim    stand still, time the strike, fight one fish
        trap   wait   pick a spot, leave, come back
        net    drive  the boat IS the tool

    Use a net while sitting in a boat rented from the job ped. It streams off the
    stern and fills by DISTANCE SAILED, not by time, so a net only pays while the
    boat is moving at a sensible speed over deep enough water.
]]
Config.FishingNets = {
    Enabled = true,

    -- The three nets, in order. A net is used from the helm of a rented boat
    -- and trawls behind it while you drive; fish accumulate by the metre.
    Tiers = {
        {
            item          = 'drift_net',
            label         = 'Drift Net',
            requiredLevel = 10,
            price         = 250,
            capacity      = 20,
            integrity     = 100,
            image         = 'images/drift_net.png',
            prop          = 'custom_fishing_net_green',
        },
        {
            item          = 'trawl_net',
            label         = 'Trawl Net',
            requiredLevel = 20,
            price         = 600,
            capacity      = 30,
            integrity     = 140,
            image         = 'images/trawl_net.png',
            prop          = 'custom_fishing_net_blue',
        },
        {
            item          = 'deepsea_net',
            label         = 'Deep Sea Net',
            requiredLevel = 32,
            price         = 1300,
            capacity      = 40,
            integrity     = 190,
            image         = 'images/deepsea_net.png',
            prop          = 'custom_fishing_net_red',
        },
    },

    -- Metres of water needed before a net may go out.
    MinDepth = 4.0,

    -- true loses the net item when it tears; false hands it back damaged.
    BreakLosesNet = true,

    -- What a haul contains, per depth band. `weight` is relative, not a percentage.
    Loot = {
        shallow = {
            { 'sardine',      weight = 90 },
            { 'roach',        weight = 80 },
            { 'jacksmelt',    weight = 55 },
            { 'surfperch',    weight = 30 },
            { 'yellow_perch', weight = 25 },
        },
        mid = {
            { 'mackerel',    weight = 85 },
            { 'sardine',     weight = 50 },
            { 'calico_bass', weight = 40 },
            { 'rockfish',    weight = 35 },
            { 'eel',         weight = 25 },
            { 'catfish',     weight = 20 },
        },
        deep = {
            { 'mackerel',   weight = 55 },
            { 'rockfish',   weight = 40 },
            { 'barracuda',  weight = 25 },
            { 'yellowtail', weight = 20 },
            { 'salmon',     weight = 15 },
        },
        abyss = {
            { 'mackerel',      weight = 40 },
            { 'barracuda',     weight = 30 },
            { 'yellowtail',    weight = 25 },
            { 'white_seabass', weight = 18 },
            { 'tuna',          weight = 12 },
        },
    },

    -- Experience per haul, and whether trawling through a golden zone pays the
    -- hotspot bonus.
    Experience   = 3,
    HotspotBoost = true,

}

--[[
    SPEARFISHING

    The only way to fish that you do IN the water, and it takes sharks and
    nothing else. No rod lands one and no net scoops one, which is the whole
    reason the system exists — a third way to catch the same fish would be a
    reskin.

    Sharks only exist while a hunt is accepted. No hunt, no sharks, anywhere:
    that is what keeps them an event instead of scenery, and it means no spawn
    loop runs for divers who are not hunting.

    Air is optional. See Breath below — the tank buys comfort, not access.
]]
Config.Speargun = {
    Enabled = true,

    -- Late-game on purpose: the gun is expensive, sharks are the top of the
    -- price table, and the hunt asks you to swim into deep water on limited air.
    RequiredLevel = 20,

    Item    = 'speargun',   -- the gun
    Ammo    = 'spear',      -- one is consumed per shot
    Harvest = 'shark',      -- what a speared shark gives you
    Tank    = 'dive_tank',  -- optional air, see Breath

    -- The marker over a shark. Underwater a carcass on a dark sea bed is nearly
    -- invisible. LiveSharks marks the living ones too, which does hand the
    -- player the hunt — set it false to mark only what you have already hit.
    SharkMarker = {
        enabled    = true,
        LiveSharks = true,
        Distance   = 60.0,
        type       = 0,
        height     = 1.2,
        bob        = true,
        size       = { x = 0.6, y = 0.6, z = 0.5 },
        color      = { r = 59, g = 130, b = 246, a = 190 },
    },

    -- Metres a shot carries, and milliseconds to reload between shots.
    Range    = 50.0,

    -- Every shot costs a spear. A miss is gone for good; on a hit, this is the
    -- % chance the shaft is still good when you cut the shark loose. Seconds is
    -- how long a missed spear stays stuck in the sea bed before it is cleaned up.
    RecoverChance    = 50,

    -- true takes the gun off you when a shark kills you.
    LoseGunOnDeath = false,

    -- The shot, played through xsound at the shooter so it fades with distance.
    -- Does nothing without xsound running.
    Sound = { Enabled = true, Volume = 0.35 },

    -- AIR. Our tank is deliberately not called `diving_gear`: that name belongs
    -- to another resource, and an inventory item has exactly one owner.
    --
    -- The tank is a SUPPLY, not a longer breath. Underwater it drains a second
    -- per second and a gauge counts it down; on the surface it refills at Regen
    -- per second. While there is air left you cannot drown, and the moment it
    -- runs dry the game takes over and drowns you on its own clock.
    --
    -- With no tank you have GTA's own lungs, about forty seconds. The hunt zones
    -- are placed so that is tight but possible.
    --
    -- Shop decides whether it is on the fishing shop's shelf, never whether the
    -- item works:
    --   'auto'   hidden while ExternalResource is running, shown when it is not
    --   'always' always sold here
    --   'never'  never sold here
    Breath = {
        Shop             = 'always',
        ExternalResource = 'qs-treasure-hunter',
        Seconds          = 600,
        Regen            = 5,
    },

    Sharks = {
        Models = { 'a_c_sharktiger', 'a_c_sharkhammer' },

        -- Every shark draws a mood on spawn and you cannot tell which by
        -- looking. Relative weights, not percentages.
        --   aggressive   comes at you once it notices you
        --   skittish     leaves the moment it notices you
        --   indifferent  ignores you until you shoot
        Temperaments = {
            aggressive  = 35,
            skittish    = 40,
            indifferent = 25,
        },

        -- % chance a shark that noticed you actually attacks. 0 means nothing
        -- ever bites: they still notice and close, they just do not commit.
        -- Rolled once per shark and remembered.
        AttackChance = 0,

    },

    -- THE HUNT. Accepted like any other job task — it is a row in Config.Tasks
    -- with a `hunt` block on it. A zone is drawn at random per hunt.
    --
    -- CHECK THESE ON YOUR OWN MAP: they are open water on a stock map, but a map
    -- replacement can put land under one, and a shark hunt on a hillside is a
    -- shark hunt nobody can finish.
    Hunt = {
        Zones = {
            { label = 'Paleto Deep',    coords = vector3(-1600.0, 5900.0, 0.0),  radius = 60.0 },
            { label = 'Chumash Trench', coords = vector3(-3400.0, 1100.0, 0.0),  radius = 60.0 },
            { label = 'Catfish Shelf',  coords = vector3(3600.0, 5300.0, 0.0),   radius = 60.0 },
            { label = 'Del Perro Drop', coords = vector3(-2000.0, -1400.0, 0.0), radius = 60.0 },
        },

        -- Sharks alive at once, milliseconds before a dead one is replaced, and
        -- the depth band they swim in.
        Alive     = 3,

        Blip = { sprite = 780, color = 1, scale = 0.9, alpha = 80 },

        -- A ring on the water over the hunt zone. Leaving size x/y nil draws it
        -- at the zone radius, so the marker IS the zone.
        Marker = {
            enabled  = true,
            type     = 1,
            height   = 0.5,
            distance = 250.0,
            bob      = false,
            size     = { x = nil, y = nil, z = 2.0 },
            color    = { r = 59, g = 130, b = 246, a = 90 },
        },
    },
}

--[[
    THE ADMIN PANEL

    One command and one screen. Everything in this file can be changed from it,
    and its Events tab opens a tournament or a golden zone and shows what is
    already running so you can stop it.

    A setting changed there is SAVED, not applied: it takes effect the next time
    the resource restarts, and the panel says so until it does. Swapping a table
    out from under code that is already using it is not a settings change.

    The permission is checked on the SERVER every time — on opening the panel and
    again on every button inside it.

    `command.fishing` is used as the ACE rather than a name of our own because
    nearly every server.cfg already carries `add_ace group.admin command allow`,
    which grants the whole `command.*` space. An existing admin can use this
    with nothing to configure.
]]
Config.AdminPanel = {
    Enabled = true,

    -- Grant with:  add_ace group.admin command.fishing allow
    Ace = 'command.fishing',

    -- Chat command that opens it. '' removes the command.
    ConfigCommand = 'fisheradmin',
}

-- The Guide button on the job panel: how the job works, read in game rather
-- than on your Discord. It can also drop the tournament zones on the map.
Config.WaterGuide = {
    Enabled = true,  -- false hides the Guide button entirely
    Blips   = true,  -- let players put the tournament zones on their map

    BlipSprite = 317,
    BlipColor  = 5,
}

--[[
    ACHIEVEMENTS

    Opened from the job panel, next to the guide.

    The species list is NOT written here: one entry is generated for every fish
    in Config.Fish, so add a fish and its achievement appears on its own. What is
    written here is everything that is not "catch one of these".

      id           unique, and what the database stores. Renaming one makes every
                   player lose that unlock, so pick it once.
      icon         a Font Awesome name from the list in AchievementsView.jsx
      type         totalCatches | speciesCount | trophies | released | heaviest
      value        the number that has to be reached
      reward       optional money paid once, when it unlocks
      experience   optional experience paid once
]]
Config.Achievements = {
    Enabled = true,

    -- Paid when a species achievement (the generated ones) unlocks.
    SpeciesReward = { money = 250, experience = 300 },

    List = {
        -- ── Milestones ──
        { id = 'first_catch',   icon = 'fish',        type = 'totalCatches', value = 1,    reward = 100,  experience = 150 },
        { id = 'catch_50',      icon = 'fish',        type = 'totalCatches', value = 50,   reward = 500,  experience = 750 },
        { id = 'catch_250',     icon = 'fish',        type = 'totalCatches', value = 250,  reward = 2000, experience = 3000 },
        { id = 'catch_1000',    icon = 'crown',       type = 'totalCatches', value = 1000, reward = 8000, experience = 12000 },

        -- ── Variety ──
        { id = 'species_3',     icon = 'layerGroup',  type = 'speciesCount', value = 3,    reward = 400,  experience = 500 },
        { id = 'species_6',     icon = 'layerGroup',  type = 'speciesCount', value = 6,    reward = 1200, experience = 1500 },
        { id = 'species_all',   icon = 'medal',       type = 'speciesCount', value = 10,   reward = 6000, experience = 9000 },

        -- ── Trophies ──
        { id = 'trophy_1',      icon = 'trophy',      type = 'trophies',     value = 1,    reward = 750,  experience = 1000 },
        { id = 'trophy_10',     icon = 'trophy',      type = 'trophies',     value = 10,   reward = 3500, experience = 5000 },
        { id = 'heavy_25',      icon = 'weightHanging', type = 'heaviest',   value = 25,   reward = 1500, experience = 2000 },
        { id = 'heavy_100',     icon = 'weightHanging', type = 'heaviest',   value = 100,  reward = 5000, experience = 7000 },
        -- The two length achievements that used to sit here are gone with the
        -- measurement. Their ids stay retired: reusing `long_150` for something
        -- else would hand the new goal to everyone who ever earned the old one.
        { id = 'heavy_300',     icon = 'weightHanging', type = 'heaviest',   value = 300,  reward = 9000, experience = 12000 },

        -- ── Conservation ──
        { id = 'released_10',   icon = 'water',       type = 'released',     value = 10,   reward = 600,  experience = 1200 },
        { id = 'released_100',  icon = 'handHoldingHeart', type = 'released', value = 100, reward = 4000, experience = 8000 },
    },
}

--[[
    CAMPFIRES AND COOKING

    Burn some wood on the sand, thread a fish onto a skewer, hold it over the
    flames and keep turning it. Take it off at the right moment and you have a
    cooked skewer; leave it and you have a burnt one.

    It is the one thing you can do with a fish other than sell it, and the only
    activity here that needs something the water cannot give you: wood.
]]
Config.Campfire = {
    Enabled = true,

    -- Chat command to build a fire. false leaves only the wood item.
    Command = 'campfire',

    -- Ask before spending the wood. false builds on the click.
    Confirm = true,

    -- What a fire costs: any ONE of these items, Amount of it. These three come
    -- from qs-lumberjack. Name an item your inventory does not have and nobody
    -- can light a fire (the console says so).
    Fuel = {
        Items  = { 'oak_wood', 'pine_wood', 'maple_wood' },
        Amount = 3,
    },

    -- Hunger each skewer restores, as a % of the bar. Raw cannot be eaten.
    -- Only read off ox_inventory — under ox the same numbers live in the items'
    -- own client.status blocks. Edit both if you change one.
    Food = {
        ['brochette_fish_cooked'] = 25,
        ['brochette_fish_burn']   = 6,
    },

    -- Minutes a fire burns, on the server's clock: it goes out at the same
    -- second for everybody, and anything still on it is handed back as it is.
    BurnMinutes = 20,

    --[[
        How deep the fire sits, in metres.

        The prop's origin is not at its base, so it is lowered onto the ground
        rather than dropped on top of it. -0.8 is right for prop_beach_fire on
        the stock map.

        Raise it toward 0 if the logs sink into the ground on yours -- a
        replaced beach, an MLO floor or a custom prop can all sit differently.
        Lower it if the fire floats. It moves the prop only; the marker, the
        flames and where you stand to cook all follow the ground itself.
    ]]
    PropZ = -0.8,

    -- Fires one player may have going, and metres between them. Anyone may
    -- cook on anyone's fire.
    Limit   = 2,

    -- The marker over every fire, including other people's.
    -- Shapes: https://docs.fivem.net/docs/game-references/markers/
    Marker = {
        enabled  = true,
        type     = 0,
        height   = 1.4,
        distance = 40.0,
        bob      = true,
        size     = { x = 0.25, y = 0.25, z = 0.18 },
        color    = { r = 59, g = 130, b = 246, a = 170 },
    },

    Ground = {
        -- No fires on water. Roads, concrete and indoor floors are always
        -- refused as well.
        NoWater = true,

        -- Your own no-build circles. `label` is shown in the refusal, so name
        -- them the way a player would say them out loud.
        Zones = {
            {
                label  = 'the fishing shop',
                coords = vector3(Config.StartJob.ped.coords.x,
                                 Config.StartJob.ped.coords.y,
                                 Config.StartJob.ped.coords.z),
                radius = 12.0,
            },
            {
                label  = 'the boat dock',
                coords = vector3(Config.BoatRental.Spawn.x,
                                 Config.BoatRental.Spawn.y,
                                 Config.BoatRental.Spawn.z),
                radius = 20.0,
            },
        },
    },

    -- The three items handed over; they already exist in the items files.
    -- Raw is both an outcome and an ingredient: it can go back over a fire.
    Items = {
        Raw    = 'brochette_fish_raw',
        Cooked = 'brochette_fish_cooked',
        Burnt  = 'brochette_fish_burn',
    },

    Cook = {
        -- Seconds OVER THE FIRE, not since you started: the clock only runs
        -- while the skewer is within HeatRange of the flames. Under ToCooked
        -- it is raw, between the two it is done, past ToBurnt it is charcoal.
        -- The cooking bar is drawn to scale from these two.
        ToCooked = 25.0,
        ToBurnt  = 32.0,

        -- false cooks from the ordinary third-person view instead of swinging
        -- the camera onto the skewer. The mouse still turns the fish.
        Camera = { Enabled = true },

        -- Every fish in Config.Fish is cookable except the ones named here.
        Exclude = {
            shark = true,
        },

        -- Experience for a skewer that came off the fire cooked.
        -- A burnt one pays nothing.
        Experience = 6,
    },
}

-- ============================================================================
--  4. LEVELS & MISSIONS
-- ============================================================================

--[[
    DISCORD WEBHOOKS

    Off by default. Paste a webhook URL into `Url`, set Enabled to true, and
    switch on the events you care about.

    Each event takes one of three values:
        true      send it, to the shared Url above
        false     do not send it
        "https://…"  send it to a channel of its own

    That last one is the useful one: money and experience can go to a staff
    channel while missions go somewhere everybody can see.
]]
Config.Webhooks = {
    Enabled = false,
    Url     = '',

    -- How the bot presents itself. Avatar takes an image URL, or '' for none.
    Name      = 'qs-fishingjob',
    Avatar    = '',
    Timestamp = true,

    Events = {
        -- A player (or a crew leader) takes a mission from the panel.
        MissionStarted   = true,

        -- The mission's fish are all in and it pays out.
        MissionFinished  = true,

        -- Abandoned from the panel, or left behind by disconnecting.
        MissionAbandoned = true,

        -- Money handed to a player: a mission payout or a sale at the shop.
        MoneyPaid        = true,

        -- Experience granted, with the level before and after.
        ExperienceGiven  = true,

        -- An admin changed a setting from the panel. Worth keeping on: it is
        -- the audit trail for who moved what.
        ConfigChanged    = true,
    },
}

-- What a level is worth, and what the next one costs. The first three are perks
-- that stack per level up to Config.MaxBonusLevel; the last two set the curve.
Config.LevelExperience = {
    FightEase = 0.5,        -- % off the reel-in difficulty per level
    ExtraCatchChance = 0.5, -- % added to the bonus-fish chance per level
    BiteTimeReduction = 1,  -- % taken off the bite wait per level
    BaseExperience = 3500,  -- Experience required for level 1
    GrowthFactor = 1.1,     -- How much more each level needs (endless levelling)
}

-- Highest level the perks above keep scaling to. Without a cap a long-lived
-- character eventually reaches 100% instant catches and the minigame stops
-- happening at all. Levelling itself is not capped, only the bonuses.
Config.MaxBonusLevel = 60

Config.MaxPartyMembers = 4 -- Crew size, including the leader

--[[
    HOW A CREW IS PAID

    'members'  every member gets the mission's full money and experience.
               A crew of four on a mission paying 2000 costs the server 8000.

    'split'    the money and the experience are divided between the members
               present when it completes. That same mission pays 500 each.

    Worth knowing before choosing: `fishAmount` does NOT scale with crew size,
    so four players bring in the same ten fish one player would. On 'members'
    that is four times the pay for the same work, which is the generous setting
    and the one this ships with so an existing server's economy does not move.

    Shares round DOWN and never fall below 1, so a small reward split many ways
    still pays something rather than reading as a bug. Anyone who left before it
    completed is already out of the crew and does not dilute the share.
]]
Config.MissionPayout = 'members'

--[[
    How often a single cast lands more than one fish.

    One fish is the rule and more than one is an event: `Chance` per cent of
    successful casts roll again across 2..maxDrop, and everything else lands
    exactly one however generous the species' maxDrop is.

    At 4 that is roughly one cast in twenty-five, and only for species that could
    drop more than one to begin with.
]]
Config.MultiCatch = {
    Chance = 4,
}

-- Metres someone must be within to be invited into the crew. Checked on the
-- server, so a modified client cannot skip it. 0 turns the check off.
--
-- It also keeps the crew tiles showing faces: the panel photographs each
-- member's ped, and a ped only exists on your machine while its player is near
-- you. Raise this past the streaming range and distant members fall back to
-- their initials.
Config.InviteDistance = 20.0

-- The missions players pick from the job panel. `fishAmount` and `fishRequired`
-- are read in pairs: the first amount belongs to the first fish, and so on.
Config.Tasks = {
    {
        taskOrder = 1, -- Do not touch
        name = "Fresh Catch",
        img = "fisher_img1.png",
        description = "Fill your basket with Carps.",
        recommendedPlayers = { 1, 4 },
        levelRequired = 1,
        experience = 1000,
        fishAmount = { 10 },
        fishRequired = { "roach" },
        money = 80,
    },
    {
        taskOrder = 2,
        name = "River Patrol",
        img = "fisher_img2.png",
        description = "Carps and Perchs roam these waters.",
        recommendedPlayers = { 1, 4 },
        levelRequired = 2,
        fishAmount = { 5, 3 },
        fishRequired = { "roach", "sardine" },
        experience = 1500,
        money = 110
    },
    {
        taskOrder = 3,
        name = "Bulk Delivery",
        img = "fisher_img3.png",
        description = "Gather Mackerel and Snapper in bulk.",
        recommendedPlayers = { 1, 4 },
        levelRequired = 4,
        fishAmount = { 8, 4 },
        fishRequired = { "mackerel", "rockfish" },
        experience = 2000,
        money = 330
    },
    -- {
    --     taskOrder = 4,
    --     name = "Trophy Hunt",
    --     img = "fisher_img1.png",
    --     description = "Search for Pike, Trout and Salmon trophies.",
    --     recommendedPlayers = { 1, 4 },
    --     levelRequired = 7,
    --     fishAmount = { 10, 5, 3 },
    --     fishRequired = { "pike", "catfish", "salmon" },
    --     experience = 2500,
    --     money = 570
    -- },
    -- {
    --     taskOrder = 5,
    --     name = "Deep Water Duty",
    --     img = "fisher_img2.png",
    --     description = "Grouper and Tuna wait in deep waters.",
    --     recommendedPlayers = { 1, 4 },
    --     levelRequired = 11,
    --     fishAmount = { 10, 6 },
    --     fishRequired = { "yellowtail", "tuna" },
    --     experience = 3500,
    --     money = 980
    -- },
    -- {
    --     taskOrder = 6,
    --     name = "Legendary Catch",
    --     img = "fisher_img3.png",
    --     description = "Hunt Tuna, Grouper and the mighty Marlin.",
    --     recommendedPlayers = { 1, 4 },
    --     levelRequired = 16,
    --     fishAmount = { 10, 7, 2 },
    --     fishRequired = { "white_seabass", "tuna", "swordfish" },
    --     experience = 3000,
    --     money = 1400
    -- },
    -- {
    --     taskOrder = 7,
    --     name = "Harbor Supplies",
    --     img = "fisher_img1.png",
    --     description = "Bring in Snapper, Tuna and Marlin for the docks.",
    --     recommendedPlayers = { 1, 4 },
    --     levelRequired = 22,
    --     fishAmount = { 10, 7, 5 },
    --     fishRequired = { "lingcod", "tuna", "horn_shark" },
    --     experience = 4000,
    --     money = 1600
    -- },

    --[[
            THE SHARK HUNT — the one task with a place.

            Every other row above is a shopping list you can finish wherever you
            already were. This one marks a zone and the quarry only exists inside it.

            The `hunt` block is the only new thing: fishRequired/fishAmount count
            speared sharks exactly the way they count rod-caught roach, and the
            payout is the same payout. A task without a `hunt` block behaves exactly
            as it always has.

            Accepting it is what makes sharks exist. Abandon it, finish it, or never
            take it, and there are none anywhere on the map.
        ]]
    {
        taskOrder = 8,
        name = "Shark Hunt",
        img = "fisher_img4.png",
        description = "Take a speargun into deep water. Bring back three sharks.",
        recommendedPlayers = { 1, 4 },
        levelRequired = 20,
        fishAmount = { 3 },
        fishRequired = { "shark" },
        experience = 6000,
        money = 1200,

        -- Marks a zone and puts sharks in it. Zones, counts and depths all live
        -- in Config.Speargun.Hunt.
        hunt = true,
    },
}

-- ============================================================================
--  5. GEAR & SHOP
--  Everything listed here is what the shop sells. Prices and level locks are
--  re-checked on the server, so this table is the only place to change them.
-- ============================================================================

--[[
    HOW EVERY PRICE IN THIS FILE IS ANCHORED

    The fish is the unit. One average fish sells for about 20 (the table runs 3
    to 72, plus the shark at 150), and a decent session lands twenty or thirty of
    them — so a session is roughly 400 to 600.

    Every price below is a multiple of that. If you change what fish are worth,
    scale these with them or the whole economy tilts.
]]

--[[
    The gear that is not a rod attachment.

    `wooden_rod` is the starter rod and the fallback: it is what the script
    assumes a player is holding when none of the rod tiers below are in their
    bag. The tackle box opens the attachment screen.

    Everything here shows in the shop's EQUIPMENT tab. `requiredLevel` is
    optional and defaults to 1; `image` is optional too, and only worth setting
    when the artwork is not named after the item.
]]
-- The shop's gear shelf. `requiredLevel` hides a row until the player gets
-- there; leave it out to sell from level 1. Rod attachments have their own
-- table further down (Config.FishingAttachments).
Config.FishingEquipment = {
    wooden_rod  = { item = "wooden_rod",  label = "Wooden Rod",  price = 20 },
    fishing_kit = { item = "fishing_kit", label = "Fishing Kit", price = 20 },

    crab_trap = {
        item          = "crab_trap",
        label         = "Crab Trap",
        price         = 80,
        requiredLevel = 5,
        image         = "images/crab_trap.png",
    },
    skewer_grill_boat = {
        item          = "skewer_grill_boat",
        label         = "Skewer Grill Boat",
        price         = 1400,
        requiredLevel = 12,
        image         = "images/skewer_boat.png",
    },
    speargun = {
        item          = "speargun",
        label         = "Speargun",
        price         = 900,
        requiredLevel = 20,
        image         = "images/speargun.png",
    },
    spear = {
        item          = "spear",
        label         = "Spear",
        price         = 8,
        requiredLevel = 20,
        image         = "images/spear.png",
    },
    dive_tank = {
        item          = "dive_tank",
        label         = "Dive Tank",
        price         = 150,
        requiredLevel = 20,
        image         = "images/dive_tank.png",
    },
}

--[[
    ROD TIERS

    A better rod buys more slots and a bigger bonus to everything fitted to it,
    and costs a higher chance of snapping when you lose a fish. The rod that
    lands trophies is also the rod you are most likely to break.

      item           the inventory item. Must exist in your inventory.
      label          shown in the shop and the tackle box
      requiredLevel  gates buying it AND using it
      price          shop price
      slots          how many of the four slots it carries. They fill in order;
                     the rest show locked with the rod that would unlock them.
      bonusScale     multiplier on every attachment fitted to it. 1.0 is face
                     value, 1.5 is half again.
      breakChance    % chance of snapping when a fish is lost. Overrides
                     Config.FishingRodBreakChance for this rod.
      perks          flat bonuses the rod itself carries, on top of anything
                     fitted. Same keys as attachment bonuses.

    Order matters: keep them worst to best. The best rod the player owns is the
    one they are using.
]]
--
-- `image` is the shop icon, from web/public/images/.
-- `palette` is which of the five colour schemes in web/src/components/rodModel.js
-- the 3D rod in the tackle box is painted with, so the rod on screen is the rod
-- you are actually holding.
Config.RodTiers = {
    {
        item = "wooden_rod", label = "Wooden Rod", requiredLevel = 1, price = 20,
        image = "images/wooden_rod.png", palette = 1,
        slots = 1, bonusScale = 1.0, breakChance = 10,
        perks = {},
    },
    {
        item = "carbon_rod", label = "Carbon Rod", requiredLevel = 3, price = 120,
        image = "images/carbon_rod.png", palette = 2,
        slots = 2, bonusScale = 1.15, breakChance = 14,
        perks = { biteTimeReduction = 5 },
    },
    {
        item = "composite_rod", label = "Composite Rod", requiredLevel = 8, price = 350,
        image = "images/composite_rod.png", palette = 3,
        slots = 3, bonusScale = 1.35, breakChance = 19,
        perks = { biteTimeReduction = 6, specimenSize = 6 },
    },
    {
        item = "tournament_rod", label = "Tournament Rod", requiredLevel = 16, price = 700,
        image = "images/tournament_rod.png", palette = 4,
        slots = 4, bonusScale = 1.6, breakChance = 25,
        perks = { fightEase = 4, specimenSize = 12, lineStrength = 8 },
    },
    {
        item = "master_rod", label = "Master Rod", requiredLevel = 28, price = 1500,
        image = "images/master_rod.png", palette = 5,
        slots = 4, bonusScale = 2.0, breakChance = 34,
        perks = { fightEase = 6, extraCatchChance = 6, specimenSize = 20, lineStrength = 12 },
    },
}

-- true to play a short animation when the rod is taken out or put away
Config.FishingRodWithdrawAnimation = false

-- The fishing animations live in client/fishing.lua, not here: they are part of
-- how the job looks rather than something a server tunes, and keeping them in
-- the escrowed side means a player cannot rewrite them.

--[[
    Rod attachments, grouped by the slot they fit into.

      bait  consumed on every catch; each fish has a favourite
      hook  fightEase         — % off how hard the reel-in fights
      reel  extraCatchChance  — % chance to pull up one extra fish
      line  biteTimeReduction — % off the wait before a bite

    Any slot can carry any bonus, and several at once — the four above are only
    how the stock catalogue is arranged. Every bonus the script understands:

      fightEase          % off the difficulty of the reel-in.
                         Capped by Config.FightDifficulty.MaxEase.
      extraCatchChance   % chance to pull up one extra fish
      biteTimeReduction  % off the wait before a bite
      specimenSize       % push toward the big end of a species' size range. Not
                         a trophy chance: it makes every fish run bigger, and
                         bigger fish cross the trophy line more often. Each point
                         is worth Config.FishStats.GearBonusPerPoint.
      lineStrength       % more angle you can pull through before the line snaps
      rodDurability      % off the rod's chance of breaking when you lose a fish
      baitSaver          % chance a cast does not use up the bait

    `requiredLevel` gates both buying the item and fitting it.
]]
Config.FishingAttachments = {
    ["bait"] = {
        { item = "earthworms",  image = "images/earthworms.png",  label = "Earthworms",  requiredLevel = 1, price = 1 },
        { item = "crickets",    image = "images/crickets.png",    label = "Crickets",    requiredLevel = 1, price = 2 },
        { item = "grasshopper", image = "images/grasshopper.png", label = "Grasshopper", requiredLevel = 2, price = 2 },
        { item = "leech",       image = "images/leech.png",       label = "Leech",       requiredLevel = 3, price = 3 },
        { item = "shrimp",      image = "images/shrimp.png",      label = "Shrimp",      requiredLevel = 4, price = 3 },
        { item = "minnow",      image = "images/minnow.png",      label = "Minnow",      requiredLevel = 5, price = 4 },
        { item = "crab",        image = "images/crab.png",        label = "Crab",        requiredLevel = 6, price = 4 },
        { item = "anguile",     image = "images/anguile.png",     label = "Anguile",     requiredLevel = 8, price = 4 },
        { item = "squid",       image = "images/squid.png",       label = "Squid",       requiredLevel = 10, price = 5 }
    },

    -- Hooks lean on landing the fish: the crit that skips the fight, and how
    -- big what you hook runs.
    ["hook"] = {
        { item = "barbed_hook",  image = "images/barbed_hook.png",  label = "Barbed Hook",  requiredLevel = 2, bonus = { fightEase = 5 },  price = 25 },
        { item = "float_bobber", image = "images/float_bobber.png", label = "Float Bobber", requiredLevel = 7, bonus = { fightEase = 9, specimenSize = 5 }, price = 60 },
        { item = "circle_hook",  image = "images/circle_hook.png",  label = "Circle Hook",  requiredLevel = 15, bonus = { fightEase = 6, specimenSize = 14, baitSaver = 10 }, price = 200 }
    },

    -- Reels are about how much you bring up, and keeping the rod in one piece.
    ["reel"] = {
        { item = "spinning_reel",     image = "images/spinning_reel.png",     label = "Spinning Reel",     requiredLevel = 1, bonus = { extraCatchChance = 8 },  price = 30 },
        { item = "monofilament_reel", image = "images/monofilament_reel.png", label = "Monofilament Reel", requiredLevel = 5, bonus = { extraCatchChance = 14, specimenSize = 5 }, price = 70 },
        { item = "graphite_reel",     image = "images/graphite_reel.png",     label = "Graphite Reel",     requiredLevel = 12,  bonus = { extraCatchChance = 18, rodDurability = 18, depthRating = 8 }, price = 200 },
        { item = "deepsea_reel",      image = "images/deepsea_reel.png",      label = "Deep Sea Reel",     requiredLevel = 22, bonus = { extraCatchChance = 24, specimenSize = 10, rodDurability = 25, depthRating = 20 }, price = 500 }
    },

    -- Lines govern the wait and the fight.
    ["line"] = {
        { item = "braided_line",      image = "images/braided_line.png",      label = "Braided line",      requiredLevel = 2, bonus = { biteTimeReduction = 10 }, price = 40 },
        { item = "fluorocarbon_line", image = "images/fluorocarbon_line.png", label = "Fluorocarbon line", requiredLevel = 9, bonus = { biteTimeReduction = 18, lineStrength = 10 }, price = 90 },
        { item = "steel_leader",      image = "images/steel_leader.png",      label = "Steel Leader",      requiredLevel = 18, bonus = { biteTimeReduction = 12, lineStrength = 30, rodDurability = 15, depthRating = 14 }, price = 300 }
    },
}

-- Highest quantity the shop lets a player buy in one go, per item.
Config.MaxShopPurchase = 100

-- ============================================================================
--  6. MINIGAME
-- ============================================================================

-- Seconds the fish takes to bite after the cast. Level and line bonuses cut
-- this down, to a floor of a second and a half.
Config.BiteTime = {
    min = 5, -- seconds
    max = 10 -- seconds
}

Config.FishingRodBreakChance = 10 -- % chance the rod breaks when you lose a fish

--[[
    HOW HARD THE FISH FIGHTS

    Difficulty comes from the DEPTH, not from the rarity. Deep water is hostile
    because it is deep, so the species that live there can be common without any
    of them going soft — you should meet a swordfish often and lose to it often,
    rather than meet a boot three times and a swordfish once.

    Two inputs, added together and clamped to 1.0:

      Tiers            the fish's OWN band. A swordfish fights like a swordfish
                       wherever you hook it.
      WeightInfluence  how much the individual specimen adds on top. A record
                       fish is a harder fight than a runt of the same species.

    Enabled = false makes every fish fight the same, whatever it is and
    wherever it came from.
]]
Config.FightDifficulty = {
    Enabled = true,

    --[[
        Base difficulty by band, 0 easiest and 1 hardest.

        These are the numbers to tune while you are feeling this out. Test any
        of them straight away with `/test3 <0..1>`, which runs a fight at that
        difficulty and nothing else — no bite wait, no fish, no reward.
    ]]
    Tiers = {
        shallow = 0.10,
        mid     = 0.35,
        deep    = 0.65,
        abyss   = 0.90,
    },

}

-- ============================================================================
--  7. LEADERBOARD
--  Opened from the "Statistics" button in the job panel.
-- ============================================================================

Config.EnableLeaderboard = true -- false hides the statistics button entirely

Config.UpdateLeaderboard = 1    -- Minutes between refreshes

-- How many fishers each leaderboard tab shows. The database query is limited to
-- this number, so raising it costs query time on every refresh.
Config.MaxLeaderboardPlayers = 100

-- Money paid to the top 3 when each ranking resets.
Config.LeaderBoardRewards = {
    Daily = {      -- Resets every day at 00:00 server time
        [1] = 550, -- 1st place
        [2] = 350, -- 2nd place
        [3] = 200  -- 3rd place
    },
    Season = {     -- Resets at 00:00 on the first day of every month
        [1] = 5000,
        [2] = 3500,
        [3] = 2000
    }
}

-- ============================================================================
--  8. MARKER
-- ============================================================================
-- The floating marker that shows players who to talk to.

Config.PedMarker = {
    enabled  = true,  -- false hides it completely

    -- The shape. 0 is the upside-down cone, the usual one for "talk to this
    -- person". The full list of shapes is here:
    -- https://docs.fivem.net/docs/game-references/markers/
    type     = 0,

    height   = 1.2,   -- How high above the NPC's head it floats, in metres
    distance = 25.0,  -- How close you have to be to see it, in metres

    bob      = true,  -- Makes it drift gently up and down

    -- How big it is. Bigger numbers, bigger marker.
    size     = { x = 0.25, y = 0.25, z = 0.18 },

    -- The colour, as red / green / blue, plus how see-through it is (a).
    -- All four go from 0 to 255.
    color    = { r = 59, g = 130, b = 246, a = 170 },
}

-- ============================================================================
--  9. DEBUG
-- ============================================================================
-- Turn this on and the script explains what it is doing in the server console
-- and in the client console (F8). Useful when something is not working and you
-- want to see how far it got before it stopped.
--
-- Leave it off on a live server: it prints a lot.

Config.Debug = false

--- Prints a line, but only while Config.Debug is on.
--- Used by the rest of the script; you should not need to touch it.
function DebugPrint(...)
    if not Config.Debug then return end

    local parts = {}
    for i = 1, select('#', ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end

    print(('^5[%s]^7 %s'):format(GetCurrentResourceName(), table.concat(parts, ' ')))
end

if Config.Debug then
    print(('^3[%s]^7 debug mode is on. Turn Config.Debug off in config/config.lua to quieten it.')
        :format(GetCurrentResourceName()))
end

--[[
    THE ESPETO BOAT

    A grill boat you carry in your bag and set down on dry LAND — the Málaga
    sardine grills are old fishing boats filled with sand and dragged up the
    beach, and that is this.

    Use the item: the screen fades, the boat lands in front of you and you come
    back standing behind the counter. Every raw skewer in your bag appears on the
    rack beside you. Drag one onto the coals, turn it before that side chars,
    turn it back, and take it off cooked — or leave it and take it off charcoal.

    The interact key swaps between two views: over the counter looking out, and
    straight down at the grill. Only the second lets you drag, because only the
    second lets you see what you are dragging onto.

    Positions, cameras and layouts are in client/foodboat.lua. `/boat1` to
    `/boat9` tune them live and print what they land on.
]]
Config.FoodBoat = {
    Enabled = true,

    -- Bought in the shop and never consumed: setting the boat down keeps the
    -- item, and packing up hands it back.
    Item = 'skewer_grill_boat',

    -- What goes on the coals and what comes off them. The same three items a
    -- campfire produces, so a skewer is a skewer wherever it was cooked.
    Raw    = 'brochette_fish_raw',
    Cooked = 'brochette_fish_cooked',
    Burnt  = 'brochette_fish_burn',

    -- Metres you may walk from the boat before it packs itself up. Generous:
    -- this is a stall, and walking round it is expected.
    Place = { Leash = 12.0 },

    -- Seconds the boat stays out before packing itself up.
    -- 0 leaves it out until you pack it up or walk away.
    Duration = 900,

    -- How many skewers fit on the coals at once. This IS the difficulty: more
    -- slots means more fish to turn before they char.
    Grill = { Slots = 4 },

    -- Seconds per side. Side is how long one side needs over the coals; Burn is
    -- how long it survives before charring, so the gap between them is your
    -- window to turn it. A skewer is done when BOTH sides have had their time,
    -- and char either side and it comes off burnt.
    Cook = {
        Side = 18.0,
        Burn = 30.0,
    },

    -- The wisp of smoke under each skewer on the coals. Cosmetic only.
    Particles = { Enabled = true },

    -- The sizzle when a skewer goes down, played at the boat so it falls away
    -- with distance. Quiet on purpose: it happens several times a minute.
    Sound = { Enabled = true, Volume = 0.01 },

    -- Customers walk up, ask for a number of skewers and pay for what they get.
    -- Drag a COOKED skewer onto one to hand it over. Short of what they wanted
    -- they still take what there is; if the stall is empty they pay and the
    -- whole thing packs up.
    Queue = {
        Enabled = true,

        -- Seconds between arrivals, picked between the two. This is the pace of
        -- the whole activity: short and the coals never catch up, long and you
        -- stand watching fish cook.
        Every = { 5, 15 },

        -- How many may be waiting at once, and how many skewers one wants.
        Max   = 3,
        Wants = { 1, 3 },

        -- What one skewer pays. Charged per skewer HANDED OVER, so somebody who
        -- got half an order pays for half.
        Pay = 24,

        -- Seconds one waits before giving up and walking off, keeping (and
        -- having paid for) anything already handed over. 0 waits forever.
        Patience = 120,
    },

    -- Interact swaps between the counter and the coals; Leave packs up. They
    -- are deliberately different keys: a mistimed press should cost you a
    -- camera move, not your whole stall.
    Keys = {
        Interact = 38,   -- E
        Leave    = 177,  -- BACKSPACE
        Grab     = 24,   -- LEFT MOUSE, drag and turn
    },
}
