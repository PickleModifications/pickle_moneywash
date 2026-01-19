-- Generic MySQL-backed placed entity storage for pickle_moneywash
-- Supports multiple entity types (moneycounter now, more later).

PMW_Entities = PMW_Entities or {}

local RESOURCE = GetCurrentResourceName()

local CREATE_TABLE_SQL = [[
CREATE TABLE IF NOT EXISTS `pickle_moneywash_entities` (
  `id` VARCHAR(64) NOT NULL,
  `type` VARCHAR(64) NOT NULL,
  `coords` LONGTEXT NOT NULL,
  `heading` DOUBLE NOT NULL DEFAULT 0,
  `data` LONGTEXT NULL,
  `created_by` VARCHAR(128) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_pickle_moneywash_entities_type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]

local Cache = {
    -- [type] = { [id] = record }
    byType = {},
}

local function normalizeType(entityType)
    if type(entityType) ~= "string" then return nil end
    entityType = string.lower(entityType)
    entityType = entityType:gsub("%s+", "")
    if entityType == "" then return nil end
    return entityType
end

local function decodeCoords(value)
    if type(value) == "table" then
        local x, y, z = value.x, value.y, value.z
        if x and y and z then return vector3(tonumber(x) or 0.0, tonumber(y) or 0.0, tonumber(z) or 0.0) end
        if value[1] and value[2] and value[3] then
            return vector3(tonumber(value[1]) or 0.0, tonumber(value[2]) or 0.0, tonumber(value[3]) or 0.0)
        end
        return nil
    end
    if type(value) ~= "string" then return nil end
    local ok, decoded = pcall(json.decode, value)
    if not ok then return nil end
    return decodeCoords(decoded)
end

local function encodeCoords(coords)
    return json.encode({ x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 })
end

local function ensureTypeBucket(entityType)
    if not Cache.byType[entityType] then Cache.byType[entityType] = {} end
    return Cache.byType[entityType]
end

local function toClientRecord(record)
    -- Keep the object minimal for network usage
    return {
        id = record.id,
        type = record.type,
        coords = record.coords,
        heading = record.heading,
        data = record.data,
        created_by = record.created_by,
        created_at = record.created_at,
        updated_at = record.updated_at,
    }
end

local function rebuildClientSnapshot()
    local snapshot = {}
    for entityType, bucket in pairs(Cache.byType) do
        snapshot[entityType] = {}
        for id, record in pairs(bucket) do
            snapshot[entityType][id] = toClientRecord(record)
        end
    end
    return snapshot
end

local function upsertCache(record)
    local entityType = normalizeType(record.type)
    if not entityType then return end
    local bucket = ensureTypeBucket(entityType)
    bucket[record.id] = record
end

local function removeFromCache(entityType, id)
    entityType = normalizeType(entityType)
    if not entityType then return end
    local bucket = Cache.byType[entityType]
    if not bucket then return end
    bucket[id] = nil
end

local function sortRecords(bucket)
    local out = {}
    for _, record in pairs(bucket or {}) do
        out[#out + 1] = toClientRecord(record)
    end
    table.sort(out, function(a, b)
        -- Stable-ish ordering for UI listing (created_at if present, else id)
        if a.created_at and b.created_at then return a.created_at < b.created_at end
        return tostring(a.id) < tostring(b.id)
    end)
    return out
end

local function getCreatorIdentifier(source)
    local src = tonumber(source)
    if not src then return nil end
    local license = GetPlayerIdentifierByType(src, "license")
    if license then return license end
    local identifiers = GetPlayerIdentifiers(src)
    if identifiers and identifiers[1] then return identifiers[1] end
    return nil
end

local function generateId(entityType)
    local t = normalizeType(entityType) or "entity"
    for _ = 1, 50 do
        local id = ("%s-%d-%d"):format(t, os.time(), math.random(100000, 999999))
        if #id <= 64 then
            local bucket = Cache.byType[t]
            if not bucket or not bucket[id] then
                return id
            end
        end
    end
    -- fallback (still within 64 chars)
    return ("%s-%d"):format(t, GetGameTimer())
end

local function onMySQLReady(cb)
    if MySQL and MySQL.ready then
        MySQL.ready(function()
            cb()
        end)
        return
    end

    -- Fallback if mysql-async variant doesn't expose MySQL.ready
    CreateThread(function()
        while not MySQL or not MySQL.Async do
            Wait(200)
        end
        cb()
    end)
end

local function ensureEntityTable(cb)
    MySQL.Async.execute(CREATE_TABLE_SQL, {}, function()
        if cb then cb() end
    end)
end

local function loadAllFromDb(cb)
    MySQL.Async.fetchAll("SELECT id, type, coords, heading, data, created_by, created_at, updated_at FROM `pickle_moneywash_entities`", {}, function(rows)
        Cache.byType = {}
        for i = 1, #(rows or {}) do
            local row = rows[i]
            local entityType = normalizeType(row.type)
            local coords = decodeCoords(row.coords)
            if entityType and row.id and coords then
                local record = {
                    id = tostring(row.id),
                    type = entityType,
                    coords = coords,
                    heading = tonumber(row.heading) or 0.0,
                    data = (row.data and row.data ~= "" and json.decode(row.data)) or nil,
                    created_by = row.created_by,
                    created_at = row.created_at,
                    updated_at = row.updated_at,
                }
                upsertCache(record)
            end
        end
        if cb then cb() end
    end)
end

local function isEmptyType(entityType)
    entityType = normalizeType(entityType)
    if not entityType then return true end
    local bucket = Cache.byType[entityType]
    return (not bucket) or (next(bucket) == nil)
end

local function migrateMoneyCountersFromConfig(cb)
    -- One-time (per DB state) migration: if DB has no moneycounter entities, import config locations.
    if not isEmptyType("moneycounter") then
        if cb then cb(false) end
        return
    end

    if not Config or not Config.MoneyCounter or not Config.MoneyCounter.locations or #Config.MoneyCounter.locations == 0 then
        if cb then cb(false) end
        return
    end

    local locations = Config.MoneyCounter.locations
    local remaining = #locations
    local insertedAny = false
    if remaining <= 0 then
        if cb then cb(false) end
        return
    end

    print(("[^3%s^0] Migrating %d money counter location(s) from config into pickle_moneywash_entities..."):format(RESOURCE, remaining))

    for i = 1, #locations do
        local location = locations[i]
        local coords = location and location.coords
        local heading = location and tonumber(location.heading) or 0.0
        if type(coords) == "vector3" then
            insertedAny = true
            local id = generateId("moneycounter")
            MySQL.Async.execute(
                "INSERT INTO `pickle_moneywash_entities` (id, type, coords, heading, data, created_by) VALUES (@id, @type, @coords, @heading, @data, @created_by)",
                {
                    ["@id"] = id,
                    ["@type"] = "moneycounter",
                    ["@coords"] = encodeCoords(coords),
                    ["@heading"] = heading,
                    ["@data"] = json.encode({ migrated = true, blipEnabled = true }),
                    ["@created_by"] = "config_migration",
                },
                function()
                    remaining = remaining - 1
                    if remaining <= 0 then
                        if cb then cb(insertedAny) end
                    end
                end
            )
        else
            remaining = remaining - 1
            if remaining <= 0 then
                if cb then cb(insertedAny) end
            end
        end
    end
end

-- Public API (server)
PMW_Entities.SyncPlayer = function(target)
    local src = tonumber(target)
    if not src then return end
    TriggerClientEvent("pickle_moneywash:entities:syncAll", src, rebuildClientSnapshot())
end

PMW_Entities.BroadcastSyncAll = function()
    TriggerClientEvent("pickle_moneywash:entities:syncAll", -1, rebuildClientSnapshot())
end

PMW_Entities.GetSnapshot = function()
    return rebuildClientSnapshot()
end

PMW_Entities.GetByType = function(entityType)
    entityType = normalizeType(entityType)
    if not entityType then return {} end
    return sortRecords(Cache.byType[entityType])
end

PMW_Entities.GetOne = function(entityType, id)
    entityType = normalizeType(entityType)
    if not entityType or not id then return nil end
    local bucket = Cache.byType[entityType]
    if not bucket then return nil end
    local record = bucket[tostring(id)]
    if not record then return nil end
    return toClientRecord(record)
end

PMW_Entities.Create = function(source, entityType, payload)
    entityType = normalizeType(entityType)
    if not entityType then return nil end
    payload = payload or {}

    local coords = payload.coords
    if type(coords) == "table" then coords = decodeCoords(coords) end
    if type(coords) ~= "vector3" then return nil end

    local heading = tonumber(payload.heading) or 0.0
    local data = payload.data
    if data ~= nil and type(data) ~= "table" then return nil end

    local id = generateId(entityType)
    local createdBy = getCreatorIdentifier(source)

    local record = {
        id = id,
        type = entityType,
        coords = coords,
        heading = heading,
        data = data,
        created_by = createdBy,
        created_at = nil,
        updated_at = nil,
    }

    MySQL.Async.execute(
        "INSERT INTO `pickle_moneywash_entities` (id, type, coords, heading, data, created_by) VALUES (@id, @type, @coords, @heading, @data, @created_by)",
        {
            ["@id"] = record.id,
            ["@type"] = record.type,
            ["@coords"] = encodeCoords(record.coords),
            ["@heading"] = record.heading,
            ["@data"] = record.data and json.encode(record.data) or nil,
            ["@created_by"] = record.created_by,
        },
        function()
            -- Best-effort: refresh timestamps by reloading just-created record
            MySQL.Async.fetchAll(
                "SELECT id, type, coords, heading, data, created_by, created_at, updated_at FROM `pickle_moneywash_entities` WHERE id = @id LIMIT 1",
                { ["@id"] = record.id },
                function(rows)
                    local row = rows and rows[1]
                    if row then
                        record.created_at = row.created_at
                        record.updated_at = row.updated_at
                    end
                    upsertCache(record)
                    TriggerClientEvent("pickle_moneywash:entities:changed", -1, "create", record.type, record.id, toClientRecord(record))
                end
            )
        end
    )

    return toClientRecord(record)
end

PMW_Entities.Update = function(source, entityType, id, patch)
    entityType = normalizeType(entityType)
    id = id and tostring(id) or nil
    if not entityType or not id then return nil end
    patch = patch or {}

    local bucket = Cache.byType[entityType]
    local existing = bucket and bucket[id] or nil
    if not existing then return nil end

    local newCoords = patch.coords
    if newCoords ~= nil then
        if type(newCoords) == "table" then newCoords = decodeCoords(newCoords) end
        if type(newCoords) ~= "vector3" then return nil end
        existing.coords = newCoords
    end

    if patch.heading ~= nil then
        existing.heading = tonumber(patch.heading) or 0.0
    end

    if patch.data ~= nil then
        if type(patch.data) ~= "table" then return nil end
        existing.data = patch.data
    end

    MySQL.Async.execute(
        "UPDATE `pickle_moneywash_entities` SET coords = @coords, heading = @heading, data = @data WHERE id = @id",
        {
            ["@id"] = existing.id,
            ["@coords"] = encodeCoords(existing.coords),
            ["@heading"] = existing.heading,
            ["@data"] = existing.data and json.encode(existing.data) or nil,
        },
        function()
            MySQL.Async.fetchAll(
                "SELECT created_at, updated_at FROM `pickle_moneywash_entities` WHERE id = @id LIMIT 1",
                { ["@id"] = existing.id },
                function(rows)
                    local row = rows and rows[1]
                    if row then
                        existing.created_at = row.created_at or existing.created_at
                        existing.updated_at = row.updated_at or existing.updated_at
                    end
                    upsertCache(existing)
                    TriggerClientEvent("pickle_moneywash:entities:changed", -1, "update", existing.type, existing.id, toClientRecord(existing))
                end
            )
        end
    )

    return toClientRecord(existing)
end

PMW_Entities.Delete = function(source, entityType, id)
    entityType = normalizeType(entityType)
    id = id and tostring(id) or nil
    if not entityType or not id then return false end

    local bucket = Cache.byType[entityType]
    if not bucket or not bucket[id] then return false end

    MySQL.Async.execute(
        "DELETE FROM `pickle_moneywash_entities` WHERE id = @id",
        { ["@id"] = id },
        function()
            removeFromCache(entityType, id)
            TriggerClientEvent("pickle_moneywash:entities:changed", -1, "delete", entityType, id, nil)
        end
    )

    return true
end

PMW_Entities._encodeCoords = encodeCoords
PMW_Entities._decodeCoords = decodeCoords
PMW_Entities._normalizeType = normalizeType
PMW_Entities._removeFromCache = removeFromCache
PMW_Entities._upsertCache = upsertCache
PMW_Entities._loadAllFromDb = loadAllFromDb

-- CRUD + sync endpoints (ox_lib)
lib.callback.register("pickle_moneywash:entities:list", function(source, entityType)
    local t = normalizeType(entityType)
    if t then return PMW_Entities.GetByType(t) end
    return PMW_Entities.GetSnapshot()
end)

lib.callback.register("pickle_moneywash:entities:create", function(source, entityType, payload)
    if not IsPlayerAdmin or not IsPlayerAdmin(source) then return false end
    return PMW_Entities.Create(source, entityType, payload)
end)

lib.callback.register("pickle_moneywash:entities:update", function(source, entityType, id, patch)
    if not IsPlayerAdmin or not IsPlayerAdmin(source) then return false end
    return PMW_Entities.Update(source, entityType, id, patch)
end)

lib.callback.register("pickle_moneywash:entities:delete", function(source, entityType, id)
    if not IsPlayerAdmin or not IsPlayerAdmin(source) then return false end
    return PMW_Entities.Delete(source, entityType, id)
end)

lib.callback.register("pickle_moneywash:entities:isAdmin", function(source)
    if not IsPlayerAdmin then return false end
    return IsPlayerAdmin(source) == true
end)

RegisterNetEvent("pickle_moneywash:entities:requestSync", function()
    local src = source
    PMW_Entities.SyncPlayer(src)
end)

AddEventHandler("onResourceStart", function(res)
    if res ~= RESOURCE then return end
    onMySQLReady(function()
        ensureEntityTable(function()
            loadAllFromDb(function()
                migrateMoneyCountersFromConfig(function(migrated)
                    if migrated then
                        loadAllFromDb(function()
                            print(("[^2%s^0] Loaded placed entities (pickle_moneywash_entities)"):format(RESOURCE))
                            PMW_Entities.BroadcastSyncAll()
                        end)
                    else
                        print(("[^2%s^0] Loaded placed entities (pickle_moneywash_entities)"):format(RESOURCE))
                    end
                end)
            end)
        end)
    end)
end)

AddEventHandler("onResourceStop", function(res)
    if res ~= RESOURCE then return end
    Cache.byType = {}
end)

