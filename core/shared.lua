Templates = {}

--- Built-in defaults for Config.Props (omit keys in config to keep these).
local PROP_DEFAULTS = {
    createPropFallback = `ch_prop_fingerprint_scanner_error_01b`,
    invisibleTargetProp = `ng_proc_brick_01a`,
    moneyCounter = {
        counter = `bkr_prop_money_counter`,
        unsorted = `bkr_prop_money_unsorted_01`,
        monitorOverlay = `hei_prop_hei_monitor_overlay`,
        bagMoney = `prop_poly_bag_money`,
    },
    moneyProcessor = {
        prop = `prop_laptop_01a`,
    },
}

--- Single-level prop: GetPropModel("createPropFallback")
--- Nested prop: GetPropModel("moneyCounter", "counter")
function GetPropModel(category, key)
    local props = Config and Config.Props
    if key == nil then
        local v = props and props[category]
        if v ~= nil then return v end
        return PROP_DEFAULTS[category]
    end
    local sub = props and props[category]
    local v = sub and sub[key]
    if v ~= nil then return v end
    return PROP_DEFAULTS[category] and PROP_DEFAULTS[category][key]
end

--- Money processor world model: Config.Props.moneyProcessor.prop, else MoneyWash.processor.prop, else default.
function GetMoneyProcessorPropModel()
    local p = Config.Props and Config.Props.moneyProcessor and Config.Props.moneyProcessor.prop
    if p ~= nil then return p end
    local cfg = (Config and Config.MoneyWash and Config.MoneyWash.processor) or {}
    if cfg.prop ~= nil then return cfg.prop end
    return PROP_DEFAULTS.moneyProcessor.prop
end

function lerp(a, b, t) return a + (b-a) * t end

function v3(coords) return vec3(coords.x, coords.y, coords.z), coords.w end

function GetRandomInt(min, max, exclude)
    for i=1, 1000 do 
        local int = math.random(min, max)
        if exclude == nil or exclude ~= int then 
            return int
        end
    end
end

function debugPrint(...)
    if Config.Debug then
        print(...)
    end
end

function NumberWithCommas(x, noCurrency)
    local left, num, right = string.match(x, '^([^%d]*%d)(%d*)(.-)$')
    return (not noCurrency and "$" or "") .. left..(num:reverse():gsub('(%d%d%d)','%1,'):reverse())
end

function tolower(str)
    return string.lower(str)
end

function toupper(str)
    return string.upper(str)
end

function GetItemLabel(name)
    if Inventory.Items[name] then
        return Inventory.Items[name].label
    elseif Inventory.Items[toupper(name)] then
        return Inventory.Items[toupper(name)].label
    end
    return name
end

function GetCurrencyString(amount)
    return NumberWithCommas(amount)
end