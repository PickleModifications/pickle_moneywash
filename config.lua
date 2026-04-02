Config = {}
Config.Language = "en"
Config.Debug = true -- This enables debugging prints.
Config.RenderDistance = 100.0
Config.InteractDistance = 2.0
Config.MusicRadius = 20.0
Config.DebugListen = false -- When false, the broadcaster will not auto-listen to their own stream
Config.UseTarget = true -- This enables the use of the target system when available.
Config.XPEnabled = true -- This enables the use of the XP system.
Config.XPCategories = {
    ["money_laundering"] = {
        label = "Money Laundering",
    },
}
Config.ImageDirectory = "nui://ox_inventory/web/images/"
Config.ImageExtension = "png"
Config.WeaponsAreItems = true -- This enables the use of weapons as items. If set to false, weapons will be treated as items and not as weapons.
Config.Currency = { currency = "USD", countryCode = "en-US" } -- Look up JS currency and countryCode variables for more options. 
Config.AdminGroups = {
    -- "qbcore.admin",
    -- "qbcore.god",
    -- "god",
    -- "admin",
    -- "mod",
    -- "superadmin",
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
-- Prop model overrides (joaat / backtick hashes). Change any value to retexture or swap meshes.
-- Omitted keys fall back to built-ins in core/shared.lua (PROP_DEFAULTS).
-- Tennis balls (CreateTennisBall / prop_tennis_ball) are not configurable.
Config.Props = {
    --- Used when CreateProp is given an invalid model (fallback retry).
    createPropFallback = `ch_prop_fingerprint_scanner_error_01b`,
    --- Invisible interaction anchor when targeting with no model (NoModelTargeting).
    invisibleTargetProp = `ng_proc_brick_01a`,
    moneyCounter = {
        --- Placed counter machine, gizmo preview, interactive entity "moneycounter", GetModelDimensions.
        counter = `bkr_prop_money_counter`,
        --- Bill piles, animated bills, interactive entity "money".
        unsorted = `bkr_prop_money_unsorted_01`,
        --- DUI screen mesh + render target name "hei_mon" (must support named rendertarget if changed).
        monitorOverlay = `hei_prop_hei_monitor_overlay`,
        --- Interactive entity "moneybag" when counting completes.
        bagMoney = `prop_poly_bag_money`,
    },
    --- World + gizmo model for money processor terminals. Overrides Config.MoneyWash.processor.prop when set here.
    moneyProcessor = {
        prop = `prop_laptop_01a`,
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
    billAmount = 10, -- The amount of bills you need to place into the money counter to wash the money.
    locations = {
        -- -- Vanilla Unicorn
        -- {
        --     coords = vector3(128.0734, -1283.1941, 29.2905),
        --     heading = 119.4825
        -- },
    }
}

-- Business laundering system (processor terminals open a UI listing these businesses).
-- Duration uses your chosen unit: $ per second (endTime = now + ceil(amount / cashPerSecond))
Config.MoneyWash = {
    -- World interaction settings for placed "moneyprocessor" terminals.
    processor = {
        interactDistance = 2.0,
        validateDistance = 5.0, -- server-side anti-cheat distance check
        -- Used when Config.Props.moneyProcessor.prop is not set (same default as Config.Props).
        prop = `prop_laptop_01a`,
        propZOffset = 0.0,
    },

    -- Tiered businesses (tier is derived from array order; index 1 is tier 1 and is free to unlock).
    -- maxCapacity is the maximum total amount currently processing (active jobs) for that business.
    businesses = {
        {
            id = "corner_store",
            label = "Corner Store",
            unlockCost = 0,
            feePercent = 25,
            maxCapacity = 15000,
            cashPerSecond = 100, -- $/sec
        },
        {
            id = "car_wash",
            label = "Car Wash",
            unlockCost = 2500,
            feePercent = 20,
            maxCapacity = 30000,
            cashPerSecond = 200, -- $/sec
        },
        {
            id = "nightclub",
            label = "Nightclub",
            unlockCost = 10000,
            feePercent = 15,
            maxCapacity = 75000,
            cashPerSecond = 1000, -- $/sec
        },
    },
}