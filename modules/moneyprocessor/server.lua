-- Money processor: tiered businesses, timed jobs, withdrawable balance
-- Persists to MySQL (mysql-async).

PMW_MoneyWash = PMW_MoneyWash or {}

local RESOURCE = GetCurrentResourceName()

local TABLES_READY = false
local TABLES_READY_PROMISE = nil

local function waitForMySQLReady()
    if MySQL and MySQL.ready then
        local p = promise.new()
        MySQL.ready(function()
            p:resolve(true)
        end)
        return Citizen.Await(p)
    end

    -- Fallback for mysql-async variants without MySQL.ready
    while (not MySQL) or (not MySQL.Async) do
        Wait(200)
    end
    return true
end

local function nowSec()
    return os.time()
end

local function newJobId()
    return ("job-%d-%d"):format(nowSec(), math.random(100000, 999999))
end

local function clamp(v, min, max)
    if v < min then return min end
    if v > max then return max end
    return v
end

local function awaitMySQL(fn)
    local p = promise.new()
    fn(function(result)
        p:resolve(result)
    end)
    return Citizen.Await(p)
end

local function ensureTables()
    if TABLES_READY then return true end
    if TABLES_READY_PROMISE then
        return Citizen.Await(TABLES_READY_PROMISE)
    end

    TABLES_READY_PROMISE = promise.new()
    waitForMySQLReady()

    local createAccounts = [[
CREATE TABLE IF NOT EXISTS `pickle_moneywash_accounts` (
  `identifier` VARCHAR(128) NOT NULL,
  `withdrawable_balance` BIGINT NOT NULL DEFAULT 0,
  `unlocked_businesses` LONGTEXT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]

    local createJobs = [[
CREATE TABLE IF NOT EXISTS `pickle_moneywash_jobs` (
  `id` VARCHAR(64) NOT NULL,
  `identifier` VARCHAR(128) NOT NULL,
  `business_id` VARCHAR(64) NOT NULL,
  `amount` BIGINT NOT NULL,
  `fee_percent` DOUBLE NOT NULL DEFAULT 0,
  `net_amount` BIGINT NULL,
  `start_ts` BIGINT NOT NULL,
  `end_ts` BIGINT NOT NULL,
  `status` VARCHAR(16) NOT NULL DEFAULT 'active',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_pmw_jobs_identifier` (`identifier`),
  KEY `idx_pmw_jobs_status_end` (`status`, `end_ts`),
  KEY `idx_pmw_jobs_business` (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]

    MySQL.Async.execute(createAccounts, {}, function()
        MySQL.Async.execute(createJobs, {}, function()
            TABLES_READY = true
            local p = TABLES_READY_PROMISE
            TABLES_READY_PROMISE = nil
            if p then p:resolve(true) end
        end)
    end)

    return Citizen.Await(TABLES_READY_PROMISE)
end

local function normBusinessId(id)
    if type(id) ~= "string" then return nil end
    id = id:gsub("%s+", "")
    id = id:lower()
    if id == "" then return nil end
    return id
end

local function getMoneyLaunderingLevel(src)
    if not (Config and Config.XPEnabled) then return 1 end
    if type(GetPlayerLevel) ~= "function" then return 1 end
    local lvl = tonumber(GetPlayerLevel(src, "money_laundering")) or 1
    if lvl < 1 then lvl = 1 end
    return lvl
end

local function hasBusinessXPAccess(src, business)
    if not (Config and Config.XPEnabled) then return false end
    local req = tonumber(business and business.xpLevel) or 1
    if req <= 1 then return false end
    local lvl = getMoneyLaunderingLevel(src)
    return lvl >= req
end

local function getBusinesses()
    local list = (Config and Config.MoneyWash and Config.MoneyWash.businesses) or {}
    local out = {}
    for i = 1, #list do
        local b = list[i]
        local bid = normBusinessId(b and b.id)
        if bid then
            local cashPerSecond = tonumber(b.cashPerSecond)
            if not cashPerSecond then
                -- Backwards compat: if config still uses secondsPerCash (seconds per $1), convert.
                local secondsPerCash = tonumber(b.secondsPerCash)
                if secondsPerCash and secondsPerCash > 0 then
                    cashPerSecond = 1.0 / secondsPerCash
                end
            end
            cashPerSecond = tonumber(cashPerSecond) or 0
            if cashPerSecond < 0 then cashPerSecond = 0 end

            out[#out + 1] = {
                id = bid,
                label = b.label or bid,
                -- Tier is derived from config array order (index 1 is tier 1).
                tier = i,
                unlockCost = tonumber(b.unlockCost) or 0,
                feePercent = tonumber(b.feePercent) or 0,
                maxCapacity = tonumber(b.maxCapacity) or 0,
                cashPerSecond = cashPerSecond,
                xpLevel = tonumber(b.xpLevel) or 1,
                xpOptional = (b.xpOptional == true),
            }
        end
    end
    return out
end

local function findBusiness(businessId)
    businessId = normBusinessId(businessId)
    if not businessId then return nil end
    local list = getBusinesses()
    for i = 1, #list do
        if list[i].id == businessId then
            return list[i]
        end
    end
    return nil
end

local function decodeUnlocked(jsonStr)
    if type(jsonStr) ~= "string" or jsonStr == "" then return {} end
    local ok, decoded = pcall(json.decode, jsonStr)
    if not ok or type(decoded) ~= "table" then return {} end
    local out = {}
    for _, v in pairs(decoded) do
        local id = normBusinessId(v)
        if id then out[id] = true end
    end
    return out
end

local function encodeUnlocked(set)
    local out = {}
    for id, enabled in pairs(set or {}) do
        if enabled then out[#out + 1] = id end
    end
    table.sort(out)
    return json.encode(out)
end

local function getOrCreateAccountRow(identifier)
    if not identifier then return nil end
    ensureTables()
    local rows = awaitMySQL(function(done)
        MySQL.Async.fetchAll(
            "SELECT identifier, withdrawable_balance, unlocked_businesses FROM `pickle_moneywash_accounts` WHERE identifier=@identifier LIMIT 1",
            { ["@identifier"] = identifier },
            function(r) done(r) end
        )
    end)
    local row = rows and rows[1] or nil
    if row then return row end

    awaitMySQL(function(done)
        MySQL.Async.execute(
            "INSERT INTO `pickle_moneywash_accounts` (identifier, withdrawable_balance, unlocked_businesses) VALUES (@identifier, 0, NULL)",
            { ["@identifier"] = identifier },
            function() done(true) end
        )
    end)

    rows = awaitMySQL(function(done)
        MySQL.Async.fetchAll(
            "SELECT identifier, withdrawable_balance, unlocked_businesses FROM `pickle_moneywash_accounts` WHERE identifier=@identifier LIMIT 1",
            { ["@identifier"] = identifier },
            function(r) done(r) end
        )
    end)
    return rows and rows[1] or nil
end

local function setBalances(identifier, withdrawable, unlockedSet)
    ensureTables()
    return awaitMySQL(function(done)
        MySQL.Async.execute(
            "UPDATE `pickle_moneywash_accounts` SET withdrawable_balance=@withdrawable, unlocked_businesses=@unlocked WHERE identifier=@identifier",
            {
                ["@identifier"] = identifier,
                ["@withdrawable"] = math.floor(tonumber(withdrawable) or 0),
                ["@unlocked"] = unlockedSet and encodeUnlocked(unlockedSet) or nil,
            },
            function() done(true) end
        )
    end)
end

local function validateProcessorDistance(src, processorId)
    if not PMW_Entities or not PMW_Entities.GetOne then return false end
    if not processorId then return false end
    local record = PMW_Entities.GetOne("moneyprocessor", processorId)
    if not record or not record.coords then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pcoords = GetEntityCoords(ped)
    local dist = #(pcoords - record.coords)

    local maxDist = 5.0
    if Config and Config.MoneyWash and Config.MoneyWash.processor and Config.MoneyWash.processor.validateDistance then
        maxDist = tonumber(Config.MoneyWash.processor.validateDistance) or maxDist
    end
    return dist <= maxDist
end

local FinalizeLocks = {} -- [identifier] = true while finalizing

local function finalizeCompletedJobs(identifier, notifySrc)
    if not identifier then return end
    if FinalizeLocks[identifier] then return end
    FinalizeLocks[identifier] = true
    ensureTables()

    local now = nowSec()
    local rows = awaitMySQL(function(done)
        MySQL.Async.fetchAll(
            "SELECT id, business_id, amount, fee_percent, start_ts, end_ts FROM `pickle_moneywash_jobs` WHERE identifier=@identifier AND status='active' AND end_ts <= @now",
            { ["@identifier"] = identifier, ["@now"] = now },
            function(r) done(r) end
        )
    end)

    if not rows or #rows == 0 then
        FinalizeLocks[identifier] = nil
        return
    end

    local businessLabels = {}
    local businesses = getBusinesses()
    for i = 1, #businesses do
        businessLabels[businesses[i].id] = businesses[i].label or businesses[i].id
    end

    local totalNet = 0
    for i = 1, #rows do
        local amount = math.floor(tonumber(rows[i].amount) or 0)
        local fee = tonumber(rows[i].fee_percent) or 0
        fee = clamp(fee, 0, 100)
        local net = math.floor(amount * (1.0 - (fee / 100.0)))
        if net < 0 then net = 0 end
        rows[i].net_amount = net
        totalNet = totalNet + net
    end

    -- Mark jobs completed + store net_amount
    for i = 1, #rows do
        awaitMySQL(function(done)
            MySQL.Async.execute(
                "UPDATE `pickle_moneywash_jobs` SET status='completed', net_amount=@net WHERE id=@id",
                { ["@id"] = rows[i].id, ["@net"] = rows[i].net_amount or 0 },
                function() done(true) end
            )
        end)
    end

    -- Credit withdrawable balance
    local acct = getOrCreateAccountRow(identifier)
    local withdrawable = tonumber(acct and acct.withdrawable_balance) or 0
    withdrawable = withdrawable + totalNet
    setBalances(identifier, withdrawable, decodeUnlocked(acct and acct.unlocked_businesses))

    if notifySrc and totalNet > 0 then
        -- One completion per business max (enforced elsewhere), so per-row notify is OK.
        for i = 1, #rows do
            local label = businessLabels[tostring(rows[i].business_id)] or tostring(rows[i].business_id)
            local net = math.floor(tonumber(rows[i].net_amount) or 0)
            if net > 0 then
                ShowNotification(notifySrc, _L("pmw_processing_ready", label, GetCurrencyString(net)))
            else
                ShowNotification(notifySrc, _L("pmw_processing_ready", label, GetCurrencyString(0)))
            end
        end
    end

    FinalizeLocks[identifier] = nil
end

local function getActiveJobs(identifier)
    ensureTables()
    return awaitMySQL(function(done)
        MySQL.Async.fetchAll(
            "SELECT id, business_id, amount, fee_percent, start_ts, end_ts, status, net_amount FROM `pickle_moneywash_jobs` WHERE identifier=@identifier AND status='active' ORDER BY start_ts ASC",
            { ["@identifier"] = identifier },
            function(r) done(r or {}) end
        )
    end)
end

local function hasActiveJob(identifier, businessId)
    ensureTables()
    local row = awaitMySQL(function(done)
        MySQL.Async.fetchAll(
            "SELECT id FROM `pickle_moneywash_jobs` WHERE identifier=@identifier AND business_id=@business_id AND status='active' LIMIT 1",
            { ["@identifier"] = identifier, ["@business_id"] = businessId },
            function(r) done((r and r[1]) or nil) end
        )
    end)
    return row ~= nil
end

local function getActiveCapacity(identifier, businessId)
    ensureTables()
    local row = awaitMySQL(function(done)
        MySQL.Async.fetchAll(
            "SELECT COALESCE(SUM(amount), 0) AS total FROM `pickle_moneywash_jobs` WHERE identifier=@identifier AND business_id=@business_id AND status='active'",
            { ["@identifier"] = identifier, ["@business_id"] = businessId },
            function(r) done((r and r[1]) or nil) end
        )
    end)
    return math.floor(tonumber(row and row.total) or 0)
end

local function buildState(src, processorId)
    local identifier = GetIdentifier and GetIdentifier(src) or nil
    if not identifier then return nil end
    ensureTables()

    finalizeCompletedJobs(identifier, src)

    local acct = getOrCreateAccountRow(identifier)
    local withdrawable = math.floor(tonumber(acct and acct.withdrawable_balance) or 0)
    local unlocked = decodeUnlocked(acct and acct.unlocked_businesses)

    local unprocessed = 0
    if Inventory and Inventory.GetItemCount then
        unprocessed = math.floor(tonumber(Inventory.GetItemCount(src, "unprocessed_money")) or 0)
    end

    local businesses = getBusinesses()
    local unlockedOut = {}
    local playerLvl = getMoneyLaunderingLevel(src)
    for i = 1, #businesses do
        local b = businesses[i]
        local xpReq = tonumber(b.xpLevel) or 1
        local xpMet = (Config and Config.XPEnabled) and xpReq > 1 and playerLvl >= xpReq
        if (tonumber(b.tier) or 1) <= 1 then
            unlockedOut[b.id] = true
        elseif unlocked[b.id] then
            unlockedOut[b.id] = true
        elseif xpMet then
            -- XP can grant access without purchase.
            unlockedOut[b.id] = true
        end
    end

    local jobs = getActiveJobs(identifier)
    local jobsOut = {}
    for i = 1, #jobs do
        local r = jobs[i]
        jobsOut[#jobsOut + 1] = {
            id = r.id,
            businessId = r.business_id,
            amount = math.floor(tonumber(r.amount) or 0),
            feePercent = tonumber(r.fee_percent) or 0,
            netAmount = r.net_amount and math.floor(tonumber(r.net_amount) or 0) or nil,
            startTs = math.floor(tonumber(r.start_ts) or 0),
            endTs = math.floor(tonumber(r.end_ts) or 0),
            status = r.status,
        }
    end

    local capacity = {}
    for i = 1, #businesses do
        local b = businesses[i]
        capacity[b.id] = getActiveCapacity(identifier, b.id)
    end

    return {
        serverTime = nowSec(),
        processorId = processorId and tostring(processorId) or nil,
        balances = {
            unprocessed = unprocessed,
            withdrawable = withdrawable,
        },
        businesses = businesses,
        unlocked = unlockedOut,
        activeCapacity = capacity,
        jobs = jobsOut,
    }
end

-- Legacy API removed: counted balance no longer used (moneycounter outputs unprocessed_money items).

-- ox_lib callbacks (client will call these and return results to NUI)
lib.callback.register("pmw:processor:getState", function(source, processorId)
    local src = source
    if not validateProcessorDistance(src, processorId) then return nil end
    return buildState(src, processorId)
end)

lib.callback.register("pmw:processor:unlockBusiness", function(source, processorId, businessId)
    local src = source
    if not validateProcessorDistance(src, processorId) then return nil end

    local identifier = GetIdentifier and GetIdentifier(src) or nil
    if not identifier then return nil end
    ensureTables()

    local business = findBusiness(businessId)
    if not business then return nil end

    -- XP requirement (optional purchase bypass if xpOptional = true).
    local xpReq = tonumber(business.xpLevel) or 1
    if (Config and Config.XPEnabled) and xpReq > 1 then
        local lvl = getMoneyLaunderingLevel(src)
        if lvl >= xpReq then
            -- Already has access via XP.
            return buildState(src, processorId)
        end
        if business.xpOptional ~= true then
            return { error = "xp_required" }
        end
    end

    local tier = tonumber(business.tier) or 1
    if tier <= 1 then
        return buildState(src, processorId)
    end

    local acct = getOrCreateAccountRow(identifier)
    local unlocked = decodeUnlocked(acct and acct.unlocked_businesses)
    if unlocked[business.id] then
        return buildState(src, processorId)
    end

    local cost = math.floor(tonumber(business.unlockCost) or 0)
    if cost < 0 then cost = 0 end
    if cost > 0 then
        local cash = GetMoney and (GetMoney(src, "money") or 0) or 0
        if cash < cost then
            return { error = "not_enough_cash" }
        end
        RemoveMoney(src, cost, "money")
    end

    unlocked[business.id] = true

    local withdrawable = math.floor(tonumber(acct and acct.withdrawable_balance) or 0)
    setBalances(identifier, withdrawable, unlocked)

    return buildState(src, processorId)
end)

lib.callback.register("pmw:processor:deposit", function(source, processorId, businessId, amount)
    local src = source
    if not validateProcessorDistance(src, processorId) then return nil end

    local identifier = GetIdentifier and GetIdentifier(src) or nil
    if not identifier then return nil end
    ensureTables()

    local business = findBusiness(businessId)
    if not business then return nil end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return { error = "invalid_amount" }
    end

    local acct = getOrCreateAccountRow(identifier)
    if not acct then return nil end

    finalizeCompletedJobs(identifier)

    acct = getOrCreateAccountRow(identifier)
    local withdrawable = math.floor(tonumber(acct and acct.withdrawable_balance) or 0)
    local unlocked = decodeUnlocked(acct and acct.unlocked_businesses)

    local isUnlocked = (tonumber(business.tier) or 1) <= 1 or unlocked[business.id] == true or hasBusinessXPAccess(src, business)
    if not isUnlocked then
        return { error = "business_locked" }
    end

    -- Each business can only have one active process per player.
    if hasActiveJob(identifier, business.id) then
        return { error = "already_processing" }
    end

    -- Deposit uses unprocessed_money item (Dirty -> Counter -> Unprocessed -> Processor -> Cash)
    if not Inventory or not Inventory.GetItemCount or not Inventory.RemoveItem then
        return { error = "inventory_not_ready" }
    end
    local unprocessed = math.floor(tonumber(Inventory.GetItemCount(src, "unprocessed_money")) or 0)
    if unprocessed < amount then
        return { error = "not_enough_unprocessed" }
    end

    local maxCap = math.floor(tonumber(business.maxCapacity) or 0)
    if maxCap > 0 then
        local activeCap = getActiveCapacity(identifier, business.id)
        if (activeCap + amount) > maxCap then
            return { error = "capacity_exceeded", active = activeCap, max = maxCap }
        end
    end

    local fee = clamp(tonumber(business.feePercent) or 0, 0, 100)
    local cashPerSecond = tonumber(business.cashPerSecond) or 0
    if cashPerSecond < 0 then cashPerSecond = 0 end

    local startTs = nowSec()
    local duration = 0
    if cashPerSecond > 0 then
        duration = math.ceil(amount / cashPerSecond)
    end
    local endTs = startTs + duration
    if endTs < startTs then endTs = startTs end

    local jobId = newJobId()

    awaitMySQL(function(done)
        MySQL.Async.execute(
            "INSERT INTO `pickle_moneywash_jobs` (id, identifier, business_id, amount, fee_percent, start_ts, end_ts, status) VALUES (@id, @identifier, @business_id, @amount, @fee, @start_ts, @end_ts, 'active')",
            {
                ["@id"] = jobId,
                ["@identifier"] = identifier,
                ["@business_id"] = business.id,
                ["@amount"] = amount,
                ["@fee"] = fee,
                ["@start_ts"] = startTs,
                ["@end_ts"] = endTs,
            },
            function() done(true) end
        )
    end)

    Inventory.RemoveItem(src, "unprocessed_money", amount)

    return buildState(src, processorId)
end)

lib.callback.register("pmw:processor:withdraw", function(source, processorId, amount)
    local src = source
    if not validateProcessorDistance(src, processorId) then return nil end

    local identifier = GetIdentifier and GetIdentifier(src) or nil
    if not identifier then return nil end
    ensureTables()

    finalizeCompletedJobs(identifier)

    local acct = getOrCreateAccountRow(identifier)
    local withdrawable = math.floor(tonumber(acct and acct.withdrawable_balance) or 0)
    local unlocked = decodeUnlocked(acct and acct.unlocked_businesses)

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return { error = "invalid_amount" }
    end
    if amount > withdrawable then
        return { error = "not_enough_withdrawable" }
    end

    withdrawable = withdrawable - amount
    if withdrawable < 0 then withdrawable = 0 end
    setBalances(identifier, withdrawable, unlocked)

    AddMoney(src, amount, "money")
    return buildState(src, processorId)
end)

AddEventHandler("onResourceStart", function(res)
    if res ~= RESOURCE then return end
    CreateThread(function()
        ensureTables()
    end)
end)

-- Background watcher: finalize jobs for online players and notify immediately on completion.
CreateThread(function()
    Wait(2500)
    while true do
        ensureTables()
        local now = nowSec()
        local ids = awaitMySQL(function(done)
            MySQL.Async.fetchAll(
                "SELECT DISTINCT identifier FROM `pickle_moneywash_jobs` WHERE status='active' AND end_ts <= @now",
                { ["@now"] = now },
                function(r) done(r or {}) end
            )
        end)

        for i = 1, #ids do
            local identifier = ids[i] and ids[i].identifier or nil
            if identifier and GetSourceFromIdentifier then
                local src = GetSourceFromIdentifier(identifier)
                if src then
                    finalizeCompletedJobs(identifier, src)
                end
            end
        end

        Wait(5000)
    end
end)

