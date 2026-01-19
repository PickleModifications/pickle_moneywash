Config = {}
Config.Language = "en"
Config.Debug = true -- This enables debugging prints.
Config.RenderDistance = 100.0
Config.InteractDistance = 2.0
Config.MusicRadius = 20.0
Config.DebugListen = false -- When false, the broadcaster will not auto-listen to their own stream
Config.UseTarget = true -- This enables the use of the target system when available.
Config.ImageDirectory = "nui://ox_inventory/web/images/"
Config.ImageExtension = "png"
Config.WeaponsAreItems = true -- This enables the use of weapons as items. If set to false, weapons will be treated as items and not as weapons.
Config.Currency = { currency = "USD", countryCode = "en-US" } -- Look up JS currency and countryCode variables for more options. 
Config.AdminGroups = {
    "qbcore.admin",
    "qbcore.god",
    "god",
    "admin",
    "mod",
    "superadmin",
}
Config.TargetIcons = {
    moneycounter = "fas fa-money-bill",
    moneyprocessor = "fas fa-building",
}

-- Generic placed-entity blips (used by modules/entities/client.lua).
Config.EntityBlips = {
    moneycounter = {
        enabled = true,
        defaultEnabled = true, -- default for newly-created entities; per-entity toggle stored in DB as data.blipEnabled
        sprite = 500,
        color = 2,
        scale = 0.85,
        label = "Money Counter",
        display = 4,
        category = nil,
        radius = nil, -- Example: { size = 25.0, color = 2, alpha = 80 }
    },
    moneyprocessor = {
        enabled = true,
        defaultEnabled = true, -- default for newly-created entities; per-entity toggle stored in DB as data.blipEnabled
        sprite = 605,
        color = 5,
        scale = 0.85,
        label = "Money Processor",
        display = 4,
        category = nil,
        radius = nil,
    },
}
Config.FrameworkSettings = {
    dirtyMoney = "DEFAULT",
    usableItemMetadata = function(item, data)
        if type(data) == "table" and data.metadata then return data.metadata end
        if type(item) == "table" and item.metadata then return item.metadata end
        if type(data) == "table" and data.info then return data.info end
        if type(item) == "table" and item.info then return item.info end
        print("^1ERROR: METADATA IS WRONGLY CONFIGURED, CHECK CONFIG.LUA:^0", item, data)
    end
}
Config.MoneyCounter = {
    maxCountAmount = 10000, -- Maximum amount of money you can count at once in the money counter.
    billAmount = 3, -- The amount of bills you need to place into the money counter to wash the money.
    locations = {
        -- -- Vanilla Unicorn
        -- {
        --     coords = vector3(128.0734, -1283.1941, 29.2905),
        --     heading = 119.4825
        -- },
    }
}

-- Business laundering system (processor terminals open a UI listing these businesses).
-- Duration uses your chosen unit: seconds per $1 (endTime = now + amount * secondsPerCash)
Config.MoneyWash = {
    -- World interaction settings for placed "moneyprocessor" terminals.
    processor = {
        interactDistance = 2.0,
        validateDistance = 5.0, -- server-side anti-cheat distance check
        prop = `prop_laptop_01a`, -- rendered at the placed coords (client-side)
        propZOffset = -0.05,
    },

    -- Tiered businesses (tier 1 is free to unlock).
    -- maxCapacity is the maximum total amount currently processing (active jobs) for that business.
    businesses = {
        {
            id = "corner_store",
            label = "Corner Store",
            tier = 1,
            unlockCost = 0,
            feePercent = 25,
            maxCapacity = 15000,
            secondsPerCash = 0.25,
        },
        {
            id = "car_wash",
            label = "Car Wash",
            tier = 2,
            unlockCost = 2500,
            feePercent = 20,
            maxCapacity = 30000,
            secondsPerCash = 0.2,
        },
        {
            id = "nightclub",
            label = "Nightclub",
            tier = 3,
            unlockCost = 10000,
            feePercent = 15,
            maxCapacity = 75000,
            secondsPerCash = 0.15,
        },
    },
}