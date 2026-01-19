-- Client-side cache + admin tooling for placed entities.

PMW_EntitiesClient = PMW_EntitiesClient or {}

local EntityCache = {}
-- EntityCache[type][id] = { id,type,coords,heading,data,... }

local function normalizeType(entityType)
    if type(entityType) ~= "string" then return nil end
    entityType = string.lower(entityType)
    entityType = entityType:gsub("%s+", "")
    if entityType == "" then return nil end
    return entityType
end

local function ensureBucket(entityType)
    if not EntityCache[entityType] then EntityCache[entityType] = {} end
    return EntityCache[entityType]
end

local function vecToString(v)
    if type(v) ~= "vector3" and type(v) ~= "table" then return "unknown" end
    local x, y, z = v.x or v[1], v.y or v[2], v.z or v[3]
    if not x or not y or not z then return "unknown" end
    return ("%.3f, %.3f, %.3f"):format(x + 0.0, y + 0.0, z + 0.0)
end

PMW_EntitiesClient.GetSnapshot = function()
    return EntityCache
end

PMW_EntitiesClient.GetByType = function(entityType)
    local t = normalizeType(entityType)
    if not t then return {} end
    local bucket = EntityCache[t] or {}
    local out = {}
    for id, record in pairs(bucket) do
        out[#out + 1] = record
    end
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return out
end

PMW_EntitiesClient.GetOne = function(entityType, id)
    local t = normalizeType(entityType)
    if not t or not id then return nil end
    local bucket = EntityCache[t]
    if not bucket then return nil end
    return bucket[tostring(id)]
end

local function applySyncAll(snapshot)
    EntityCache = snapshot or {}
end

local function applyChanged(action, entityType, id, record)
    entityType = normalizeType(entityType)
    id = id and tostring(id) or nil
    if not entityType or not id then return end
    if action == "delete" then
        if EntityCache[entityType] then
            EntityCache[entityType][id] = nil
        end
        return
    end
    if action == "create" or action == "update" then
        local bucket = ensureBucket(entityType)
        bucket[id] = record
    end
end

AddEventHandler("onResourceStart", function(res)
    if res ~= GetCurrentResourceName() then return end
    TriggerServerEvent("pickle_moneywash:entities:requestSync")
end)

-- =========================
-- Blips (configurable + per-entity toggle stored in DB)
-- =========================

local Blips = {}
-- Blips[type][id] = { blip = handle, radius = handle? }

local function clearBlip(entityType, id)
    if not Blips[entityType] or not Blips[entityType][id] then return end
    local entry = Blips[entityType][id]
    if entry.radius and DoesBlipExist(entry.radius) then
        RemoveBlip(entry.radius)
    end
    if entry.blip and DoesBlipExist(entry.blip) then
        RemoveBlip(entry.blip)
    end
    Blips[entityType][id] = nil
end

local function isEntityBlipEnabled(entityType, record)
    if not Config or not Config.EntityBlips or not Config.EntityBlips[entityType] then return false end
    local cfg = Config.EntityBlips[entityType]
    if cfg.enabled ~= true then return false end

    local defaultEnabled = true
    if cfg.defaultEnabled ~= nil then
        defaultEnabled = cfg.defaultEnabled == true
    end

    local data = record and record.data
    if type(data) == "table" and data.blipEnabled ~= nil then
        return data.blipEnabled == true
    end

    return defaultEnabled
end

local function ensureBlip(entityType, record)
    if not Config or not Config.EntityBlips or not Config.EntityBlips[entityType] then return end
    local cfg = Config.EntityBlips[entityType]
    if cfg.enabled ~= true then
        if record and record.id then clearBlip(entityType, tostring(record.id)) end
        return
    end
    if not isEntityBlipEnabled(entityType, record) then
        if record and record.id then clearBlip(entityType, tostring(record.id)) end
        return
    end

    local coords = record.coords
    if not coords then return end

    if not Blips[entityType] then Blips[entityType] = {} end
    clearBlip(entityType, record.id)

    local blip, radiusBlip = CreateBlip({
        coords = { coords.x, coords.y, coords.z },
        sprite = cfg.sprite,
        color = cfg.color,
        scale = cfg.scale,
        label = cfg.label or (PMW_EntityTypes.Get(entityType) and PMW_EntityTypes.Get(entityType).label) or entityType,
        display = cfg.display,
        category = cfg.category,
        radius = cfg.radius,
        rotation = record.heading,
    })

    Blips[entityType][record.id] = { blip = blip, radius = radiusBlip }
end

local function rebuildBlipsForType(entityType)
    if Blips[entityType] then
        for id, _ in pairs(Blips[entityType]) do
            clearBlip(entityType, id)
        end
    end

    local bucket = EntityCache[entityType] or {}
    for _, record in pairs(bucket) do
        ensureBlip(entityType, record)
    end
end

local function rebuildAllBlips()
    for entityType, _ in pairs(EntityCache) do
        rebuildBlipsForType(entityType)
    end
end

-- Hook blip rebuilds into sync events
RegisterNetEvent("pickle_moneywash:entities:syncAll", function(snapshot)
    applySyncAll(snapshot)
    rebuildAllBlips()
end)

RegisterNetEvent("pickle_moneywash:entities:changed", function(action, entityType, id, record)
    applyChanged(action, entityType, id, record)
    entityType = normalizeType(entityType)
    if not entityType then return end
    if action == "delete" then
        clearBlip(entityType, tostring(id))
    elseif action == "create" or action == "update" then
        if record then
            ensureBlip(entityType, record)
        end
    end
end)

-- =========================
-- Admin tools (ox_lib + gizmo)
-- =========================

local ClientTypes = {}

PMW_EntitiesClient.RegisterType = function(entityType, def)
    local t = normalizeType(entityType)
    if not t then return false end
    def = def or {}
    if type(def.label) ~= "string" or def.label == "" then def.label = t end
    if type(def.gizmoModel) ~= "number" then
        -- Accept backtick-hashes (numbers) only for model
        def.gizmoModel = def.gizmoModel
    end
    ClientTypes[t] = def

    -- Also register in the shared registry so blip menu can list it.
    if PMW_EntityTypes and PMW_EntityTypes.Register then
        PMW_EntityTypes.Register(t, { label = def.label, description = def.description })
    end

    return true
end

PMW_EntitiesClient.GetRegisteredTypes = function()
    local out = {}
    for t, def in pairs(ClientTypes) do
        out[#out + 1] = { type = t, label = def.label or t, description = def.description }
    end
    table.sort(out, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return out
end

local function isAdmin()
    return lib.callback.await("pickle_moneywash:entities:isAdmin", false) == true
end

local function openEntityTypeMenu(entityType)
    entityType = normalizeType(entityType)
    if not entityType then return end
    local def = ClientTypes[entityType]
    if not def then return end

    local function refreshAndOpenList()
        local list = lib.callback.await("pickle_moneywash:entities:list", false, entityType) or {}
        local options = {
            {
                title = "Create new",
                description = "Place a new entry using the gizmo.",
                onSelect = function()
                    if not def.toPayloadFromGizmo then
                        return ShowNotification("^1This entity type does not support creation yet.^0")
                    end

                    local ped = PlayerPedId()
                    local startCoords = GetEntityCoords(ped) + (GetEntityForwardVector(ped) * 2.0)
                    local startHeading = GetEntityHeading(ped)

                    local gizmoResult = StartGizmoEditor({
                        model = def.gizmoModel,
                        coords = startCoords,
                        rotation = vector3(0.0, 0.0, startHeading),
                        enableCancel = true,
                    })

                    if not gizmoResult then
                        return ShowNotification("Cancelled.")
                    end

                    local payload = def.toPayloadFromGizmo(gizmoResult, nil)
                    payload.data = payload.data or {}
                    if payload.data.blipEnabled == nil and Config and Config.EntityBlips and Config.EntityBlips[entityType] then
                        local cfg = Config.EntityBlips[entityType]
                        if cfg.defaultEnabled ~= nil then
                            payload.data.blipEnabled = cfg.defaultEnabled == true
                        else
                            payload.data.blipEnabled = true
                        end
                    end
                    local created = lib.callback.await("pickle_moneywash:entities:create", false, entityType, payload)
                    if not created then
                        return ShowNotification("^1Failed to create.^0")
                    end

                    ShowNotification(("Created (%s)."):format(created.id or "unknown"))
                    TriggerServerEvent("pickle_moneywash:entities:requestSync")
                    refreshAndOpenList()
                end,
            },
        }

        if #list == 0 then
            options[#options + 1] = {
                title = ("No %s entries"):format(def.label or entityType),
                description = "Create one to get started.",
                disabled = true,
            }
        end

        for i = 1, #list do
            local rec = list[i]
            local id = rec.id

            local title = def.formatTitle and def.formatTitle(rec) or ("[%s] %s"):format(id, def.label or entityType)
            local description = def.formatDescription and def.formatDescription(rec) or ("Coords: %s"):format(vecToString(rec.coords))

            options[#options + 1] = {
                title = title,
                description = description,
                menu = ("pmw_entities_%s_%s"):format(entityType, id),
            }

            lib.registerContext({
                id = ("pmw_entities_%s_%s"):format(entityType, id),
                title = ("%s %s"):format(def.label or entityType, id),
                menu = ("pmw_entities_%s_list"):format(entityType),
                options = {
                    {
                        title = "Reposition",
                        description = "Move it using the gizmo.",
                        onSelect = function()
                            if not def.getGizmoStartFromRecord or not def.toPayloadFromGizmo then
                                return ShowNotification("^1This entity type does not support repositioning yet.^0")
                            end

                            -- Allow type-specific renderers to temporarily hide the live entity while we place
                            TriggerEvent("pickle_moneywash:entities:editStart", entityType, tostring(id))

                            local start = def.getGizmoStartFromRecord(rec)
                            local gizmoResult = StartGizmoEditor({
                                model = def.gizmoModel,
                                coords = start.coords,
                                rotation = start.rotation,
                                enableCancel = true,
                            })

                            if not gizmoResult then
                                TriggerEvent("pickle_moneywash:entities:editEnd", entityType, tostring(id))
                                return ShowNotification("Cancelled.")
                            end

                            local patch = def.toPayloadFromGizmo(gizmoResult, rec)
                            local updated = lib.callback.await("pickle_moneywash:entities:update", false, entityType, id, patch)

                            if not updated then
                                TriggerEvent("pickle_moneywash:entities:editEnd", entityType, tostring(id))
                                return ShowNotification("^1Failed to update.^0")
                            end

                            ShowNotification("Updated.")
                            TriggerServerEvent("pickle_moneywash:entities:requestSync")
                            TriggerEvent("pickle_moneywash:entities:editEnd", entityType, tostring(id))
                            refreshAndOpenList()
                        end,
                    },
                    {
                        title = "Delete",
                        description = "Permanently delete this entry.",
                        onSelect = function()
                            local ok = lib.callback.await("pickle_moneywash:entities:delete", false, entityType, id)
                            if not ok then
                                return ShowNotification("^1Failed to delete.^0")
                            end
                            ShowNotification("Deleted.")
                            TriggerServerEvent("pickle_moneywash:entities:requestSync")
                            refreshAndOpenList()
                        end,
                    },
                },
            })
        end

        lib.registerContext({
            id = ("pmw_entities_%s_list"):format(entityType),
            title = def.label or entityType,
            menu = "pmw_entities_root",
            options = options,
        })

        lib.showContext(("pmw_entities_%s_list"):format(entityType))
    end

    refreshAndOpenList()
end

local function openEntityManageMenu(entityType, id)
    entityType = normalizeType(entityType)
    if not entityType or not id then return end
    id = tostring(id)

    local def = ClientTypes[entityType]
    if not def then
        return ShowNotification("^1Unknown entity type.^0")
    end

    local rec = PMW_EntitiesClient.GetOne(entityType, id)
    if not rec then
        -- best-effort: ask server for fresh data and try again
        local list = lib.callback.await("pickle_moneywash:entities:list", false, entityType) or {}
        for i = 1, #list do
            if tostring(list[i].id) == id then
                rec = list[i]
                break
            end
        end
    end

    if not rec then
        return ShowNotification("^1Entity not found.^0")
    end

    local title = def.formatTitle and def.formatTitle(rec) or ("[%s] %s"):format(id, def.label or entityType)
    local description = def.formatDescription and def.formatDescription(rec) or ("Coords: %s"):format(vecToString(rec.coords))

    local blipEnabled = isEntityBlipEnabled(entityType, rec)

    lib.registerContext({
        id = ("pmw_manage_%s_%s"):format(entityType, id),
        title = title,
        options = {
            {
                title = ("Blip: %s"):format(blipEnabled and "ON" or "OFF"),
                description = "Toggle the blip for this entity (global).",
                onSelect = function()
                    local data = (type(rec.data) == "table" and rec.data) or {}
                    data.blipEnabled = not blipEnabled
                    local updated = lib.callback.await("pickle_moneywash:entities:update", false, entityType, id, { data = data })
                    if not updated then
                        return ShowNotification("^1Failed to update blip setting.^0")
                    end
                    ShowNotification(("Blip %s."):format((not blipEnabled) and "enabled" or "disabled"))
                    TriggerServerEvent("pickle_moneywash:entities:requestSync")
                    openEntityManageMenu(entityType, id)
                end,
            },
            {
                title = "Reposition",
                description = "Move it using the gizmo.",
                onSelect = function()
                    if not def.getGizmoStartFromRecord or not def.toPayloadFromGizmo then
                        return ShowNotification("^1This entity type does not support repositioning yet.^0")
                    end

                    TriggerEvent("pickle_moneywash:entities:editStart", entityType, id)

                    local start = def.getGizmoStartFromRecord(rec)
                    local gizmoResult = StartGizmoEditor({
                        model = def.gizmoModel,
                        coords = start.coords,
                        rotation = start.rotation,
                        enableCancel = true,
                    })

                    if not gizmoResult then
                        TriggerEvent("pickle_moneywash:entities:editEnd", entityType, id)
                        return ShowNotification("Cancelled.")
                    end

                    local patch = def.toPayloadFromGizmo(gizmoResult, rec)
                    patch.data = patch.data or rec.data
                    local updated = lib.callback.await("pickle_moneywash:entities:update", false, entityType, id, patch)
                    TriggerEvent("pickle_moneywash:entities:editEnd", entityType, id)

                    if not updated then
                        return ShowNotification("^1Failed to update.^0")
                    end

                    ShowNotification("Updated.")
                    TriggerServerEvent("pickle_moneywash:entities:requestSync")
                    openEntityManageMenu(entityType, id)
                end,
            },
            {
                title = "Delete",
                description = "Permanently delete this entry.",
                onSelect = function()
                    local ok = lib.callback.await("pickle_moneywash:entities:delete", false, entityType, id)
                    if not ok then
                        return ShowNotification("^1Failed to delete.^0")
                    end
                    ShowNotification("Deleted.")
                    TriggerServerEvent("pickle_moneywash:entities:requestSync")
                end,
            },
            {
                title = "Back to list",
                onSelect = function()
                    openEntityTypeMenu(entityType)
                end,
            },
        },
    })

    lib.showContext(("pmw_manage_%s_%s"):format(entityType, id))
end

local function openRootMenu()
    local types = PMW_EntitiesClient.GetRegisteredTypes()
    local options = {}

    if #types == 0 then
        options[#options + 1] = { title = "No entity types registered", disabled = true }
    end

    for i = 1, #types do
        local t = types[i].type
        options[#options + 1] = {
            title = types[i].label or t,
            description = types[i].description or ("Manage %s entries."):format(t),
            onSelect = function()
                openEntityTypeMenu(t)
            end,
        }
    end

    lib.registerContext({
        id = "pmw_entities_root",
        title = "Placed Entities",
        options = options,
    })

    lib.showContext("pmw_entities_root")
end

RegisterCommand("pmw_entities", function()
    if not isAdmin() then
        return ShowNotification("^1You do not have permission to use this.^0")
    end
    openRootMenu()
end, false)

-- External entry point for in-world admin prompts (e.g. money counter interaction)
PMW_EntitiesClient.OpenManage = function(entityType, id)
    openEntityManageMenu(entityType, id)
end

AddEventHandler("pickle_moneywash:entities:openManage", function(entityType, id)
    openEntityManageMenu(entityType, id)
end)

-- ============
-- Default entity types
-- ============

local function rightVectorAt(coords, heading)
    local temp = CreateTennisBall(coords.x, coords.y, coords.z)
    SetEntityRotation(temp, 0.0, 0.0, heading, 2, true)
    local _, rightVector = GetEntityMatrix(temp)
    DeleteEntity(temp)
    return rightVector
end

PMW_EntitiesClient.RegisterType("moneycounter", {
    label = "Money Counter",
    description = "Wash dirty money at this location.",
    gizmoModel = `bkr_prop_money_counter`,
    formatTitle = function(rec)
        return ("[%s] Money Counter"):format(rec.id)
    end,
    formatDescription = function(rec)
        local heading = rec.heading or 0.0
        return ("Center: %s | Heading: %.1f"):format(vecToString(rec.coords), heading + 0.0)
    end,
    getGizmoStartFromRecord = function(rec)
        local heading = rec.heading or 0.0
        local rightVector = rightVectorAt(rec.coords, heading)
        local counterPos = rec.coords + (rightVector * -0.35)
        return {
            coords = counterPos,
            rotation = vector3(0.0, 0.0, heading),
        }
    end,
    toPayloadFromGizmo = function(gizmoResult, _existing)
        local heading = (gizmoResult.rotation and gizmoResult.rotation.z) or 0.0
        local counterPos = gizmoResult.position
        local rightVector = rightVectorAt(counterPos, heading)
        local center = counterPos + (rightVector * 0.35)
        return {
            coords = { x = center.x, y = center.y, z = center.z },
            heading = heading,
            data = {},
        }
    end,
})

