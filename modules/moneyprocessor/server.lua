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
  `counted_balance` BIGINT NOT NULL DEFAULT 0,
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

local function getBusinesses()
    local list = (Config and Config.MoneyWash and Config.MoneyWash.businesses) or {}
    local out = {}
    for i = 1, #list do
        local b = list[i]
        local bid = normBusinessId(b and b.id)
        if bid then
            out[#out + 1] = {
                id = bid,
                label = b.label or bid,
                tier = tonumber(b.tier) or 1,
                unlockCost = tonumber(b.unlockCost) or 0,
                feePercent = tonumber(b.feePercent) or 0,
                maxCapacity = tonumber(b.maxCapacity) or 0,
                secondsPerCash = tonumber(b.secondsPerCash) or 0,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        return tostring(a.label) < tostring(b.label)
    end)
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
            "SELECT identifier, counted_balance, withdrawable_balance, unlocked_businesses FROM `pickle_moneywash_accounts` WHERE identifier=@identifier LIMIT 1",
            { ["@identifier"] = identifier },
            function(r) done(r) end
        )
    end)
    local row = rows and rows[1] or nil
    if row then return row end

    awaitMySQL(function(done)
        MySQL.Async.execute(
            "INSERT INTO `pickle_moneywash_accounts` (identifier, counted_balance, withdrawable_balance, unlocked_businesses) VALUES (@identifier, 0, 0, NULL)",
            { ["@identifier"] = identifier },
            function() done(true) end
        )
    end)

    rows = awaitMySQL(function(done)
        MySQL.Async.fetchAll(
            "SELECT identifier, counted_balance, withdrawable_balance, unlocked_businesses FROM `pickle_moneywash_accounts` WHERE identifier=@identifier LIMIT 1",
            { ["@identifier"] = identifier },
            function(r) done(r) end
        )
    end)
    return rows and rows[1] or nil
end

local function setBalances(identifier, counted, withdrawable, unlockedSet)
    ensureTables()
    return awaitMySQL(function(done)
        MySQL.Async.execute(
            "UPDATE `pickle_moneywash_accounts` SET counted_balance=@counted, withdrawable_balance=@withdrawable, unlocked_businesses=@unlocked WHERE identifier=@identifier",
            {
                ["@identifier"] = identifier,
                ["@counted"] = math.floor(tonumber(counted) or 0),
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

local function finalizeCompletedJobs(identifier)
    if not identifier then return end
    ensureTables()

    local now = nowSec()
    local rows = awaitMySQL(function(done)
        MySQL.Async.fetchAll(
            "SELECT id, business_id, amount, fee_percent, start_ts, end_ts FROM `pickle_moneywash_jobs` WHERE identifier=@identifier AND status='active' AND end_ts <= @now",
            { ["@identifier"] = identifier, ["@now"] = now },
            function(r) done(r) end
        )
    end)

    if not rows or #rows == 0 then return end

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
    local counted = tonumber(acct and acct.counted_balance) or 0
    local withdrawable = tonumber(acct and acct.withdrawable_balance) or 0
    withdrawable = withdrawable + totalNet
    setBalances(identifier, counted, withdrawable, decodeUnlocked(acct and acct.unlocked_businesses))
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

    finalizeCompletedJobs(identifier)

    local acct = getOrCreateAccountRow(identifier)
    local counted = math.floor(tonumber(acct and acct.counted_balance) or 0)
    local withdrawable = math.floor(tonumber(acct and acct.withdrawable_balance) or 0)
    local unlocked = decodeUnlocked(acct and acct.unlocked_businesses)

    local businesses = getBusinesses()
    local unlockedOut = {}
    for i = 1, #businesses do
        local b = businesses[i]
        if (tonumber(b.tier) or 1) <= 1 then
            unlockedOut[b.id] = true
        elseif unlocked[b.id] then
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
            counted = counted,
            withdrawable = withdrawable,
        },
        businesses = businesses,
        unlocked = unlockedOut,
        activeCapacity = capacity,
        jobs = jobsOut,
    }
end

-- Export for other modules (e.g., moneycounter)
PMW_MoneyWash.AddCountedBalance = function(identifier, amount)
    if not identifier then return false end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    ensureTables()
    local acct = getOrCreateAccountRow(identifier)
    if not acct then return false end
    local counted = math.floor(tonumber(acct.counted_balance) or 0)
    local withdrawable = math.floor(tonumber(acct.withdrawable_balance) or 0)
    local unlocked = decodeUnlocked(acct.unlocked_businesses)
    counted = counted + amount
    setBalances(identifier, counted, withdrawable, unlocked)
    return true
end

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

    local counted = math.floor(tonumber(acct and acct.counted_balance) or 0)
    local withdrawable = math.floor(tonumber(acct and acct.withdrawable_balance) or 0)
    setBalances(identifier, counted, withdrawable, unlocked)

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
    local counted = math.floor(tonumber(acct and acct.counted_balance) or 0)
    local withdrawable = math.floor(tonumber(acct and acct.withdrawable_balance) or 0)
    local unlocked = decodeUnlocked(acct and acct.unlocked_businesses)

    local isUnlocked = (tonumber(business.tier) or 1) <= 1 or unlocked[business.id] == true
    if not isUnlocked then
        return { error = "business_locked" }
    end

    if counted < amount then
        return { error = "not_enough_counted" }
    end

    local maxCap = math.floor(tonumber(business.maxCapacity) or 0)
    if maxCap > 0 then
        local activeCap = getActiveCapacity(identifier, business.id)
        if (activeCap + amount) > maxCap then
            return { error = "capacity_exceeded", active = activeCap, max = maxCap }
        end
    end

    local fee = clamp(tonumber(business.feePercent) or 0, 0, 100)
    local secondsPerCash = tonumber(business.secondsPerCash) or 0
    if secondsPerCash < 0 then secondsPerCash = 0 end

    local startTs = nowSec()
    local endTs = startTs + math.floor(amount * secondsPerCash)
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

    counted = counted - amount
    if counted < 0 then counted = 0 end
    setBalances(identifier, counted, withdrawable, unlocked)

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
    local counted = math.floor(tonumber(acct and acct.counted_balance) or 0)
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
    setBalances(identifier, counted, withdrawable, unlocked)

    AddMoney(src, amount, "money")
    return buildState(src, processorId)
end)

AddEventHandler("onResourceStart", function(res)
    if res ~= RESOURCE then return end
    CreateThread(function()
        ensureTables()
    end)
end)

