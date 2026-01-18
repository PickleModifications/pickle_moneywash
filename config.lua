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
        -- Vanilla Unicorn
        {
            coords = vector3(128.0734, -1283.1941, 29.2905),
            heading = 119.4825
        },
    }
}