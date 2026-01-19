local MoneyProcessors = {} -- [id] = record
local RenderedMoneyProcessors = {} -- [id] = { prop = entity }
local MoneyProcessorInteractions = {} -- [id] = interactionIndex
local MoneyProcessorEditing = {} -- [id] = true while being moved via gizmo

local function normalizeId(id)
    if id == nil then return nil end
    return tostring(id)
end

local function UnrenderMoneyProcessor(id)
    id = normalizeId(id)
    if not id then return end
    if RenderedMoneyProcessors[id] and RenderedMoneyProcessors[id].prop and DoesEntityExist(RenderedMoneyProcessors[id].prop) then
        DeleteEntity(RenderedMoneyProcessors[id].prop)
    end
    RenderedMoneyProcessors[id] = nil
end

local function RenderMoneyProcessor(id)
    id = normalizeId(id)
    if not id then return end
    UnrenderMoneyProcessor(id)

    local proc = MoneyProcessors[id]
    if not proc or not proc.coords then return end
    if CURRENT_INTERACTION then return end

    local cfg = (Config and Config.MoneyWash and Config.MoneyWash.processor) or {}
    local model = cfg.prop or `prop_laptop_01a`
    local zoff = tonumber(cfg.propZOffset) or 0.0

    RenderedMoneyProcessors[id] = {} -- prevent double render
    local coords = proc.coords
    local heading = proc.heading or 0.0

    local prop = CreateProp(model, coords.x, coords.y, coords.z + zoff, false, false, false)
    if prop and prop ~= 0 then
        SetEntityCollision(prop, true, true)
        SetEntityHeading(prop, heading)
        FreezeEntityPosition(prop, true)
        RenderedMoneyProcessors[id] = { prop = prop }
    else
        RenderedMoneyProcessors[id] = nil
    end
end

local function RemoveMoneyProcessorInteraction(id)
    id = normalizeId(id)
    if not id then return end
    if not MoneyProcessorInteractions[id] then return end
    DeleteInteraction(MoneyProcessorInteractions[id])
    MoneyProcessorInteractions[id] = nil
end

local function OpenProcessorUI(id)
    id = normalizeId(id)
    if not id then return end

    SetNuiFocus(true, true)

    -- Send config + open signal; UI will request state via NUI callback.
    local locale = (Language and Config and Config.Language and Language[Config.Language]) or nil
    SendNUIMessage({
        type = "setConfig",
        config = {
            currency = (Config and Config.Currency and Config.Currency.currency) or "USD",
            countryCode = (Config and Config.Currency and Config.Currency.countryCode) or "en-US",
            imageDirectory = Config and Config.ImageDirectory or nil,
            imageExtension = Config and Config.ImageExtension or "png",
            locale = locale,
        }
    })

    SendNUIMessage({
        type = "pmw_open",
        processorId = id,
    })
end

local function EnsureMoneyProcessorInteraction(id)
    id = normalizeId(id)
    if not id then return end
    local proc = MoneyProcessors[id]
    if not proc then return end
    if MoneyProcessorInteractions[id] then return end

    MoneyProcessorInteractions[id] = CreateInteraction({
        coords = proc.coords,
        heading = proc.heading or 0.0,
        label = "Money Processor",
        icon = (Config and Config.TargetIcons and Config.TargetIcons.moneyprocessor) or "fas fa-building",
    }, function()
        OpenProcessorUI(id)
    end)
end

-- Keep processors rendered/interactive as you move around
CreateThread(function()
    Wait(1000)
    while true do
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        for id, proc in pairs(MoneyProcessors) do
            if MoneyProcessorEditing[id] then
                RemoveMoneyProcessorInteraction(id)
                UnrenderMoneyProcessor(id)
                goto continue
            end

            local dist = #(pcoords - proc.coords)
            if dist <= (Config.RenderDistance or 100.0) then
                EnsureMoneyProcessorInteraction(id)
                if not RenderedMoneyProcessors[id] then
                    RenderMoneyProcessor(id)
                end
            else
                RemoveMoneyProcessorInteraction(id)
                UnrenderMoneyProcessor(id)
            end
            ::continue::
        end
        Wait(1500)
    end
end)

-- Sync from placed entities system
RegisterNetEvent("pickle_moneywash:entities:syncAll", function(snapshot)
    local bucket = snapshot and snapshot.moneyprocessor or {}
    MoneyProcessors = {}
    for id, rec in pairs(bucket) do
        if rec and rec.coords then
            MoneyProcessors[normalizeId(id)] = rec
        end
    end
end)

RegisterNetEvent("pickle_moneywash:entities:changed", function(action, entityType, id, record)
    if tostring(entityType) ~= "moneyprocessor" then return end
    id = normalizeId(id)
    if not id then return end

    if action == "delete" then
        RemoveMoneyProcessorInteraction(id)
        UnrenderMoneyProcessor(id)
        MoneyProcessors[id] = nil
        return
    end

    if action == "create" or action == "update" then
        if record and record.coords then
            MoneyProcessors[id] = record
            RemoveMoneyProcessorInteraction(id)
            UnrenderMoneyProcessor(id)
        end
    end
end)

-- Temporarily hide while an admin is repositioning via gizmo
AddEventHandler("pickle_moneywash:entities:editStart", function(entityType, id)
    if tostring(entityType) ~= "moneyprocessor" then return end
    id = normalizeId(id)
    MoneyProcessorEditing[id] = true
    RemoveMoneyProcessorInteraction(id)
    UnrenderMoneyProcessor(id)
end)

AddEventHandler("pickle_moneywash:entities:editEnd", function(entityType, id)
    if tostring(entityType) ~= "moneyprocessor" then return end
    id = normalizeId(id)
    MoneyProcessorEditing[id] = nil
    RemoveMoneyProcessorInteraction(id)
    UnrenderMoneyProcessor(id)
end)

-- Admin placement registration
CreateThread(function()
    Wait(1000)
    if not PMW_EntitiesClient or not PMW_EntitiesClient.RegisterType then return end

    PMW_EntitiesClient.RegisterType("moneyprocessor", {
        label = "Money Processor",
        description = "Deposit counted money into businesses and withdraw washed cash.",
        gizmoModel = (Config and Config.MoneyWash and Config.MoneyWash.processor and Config.MoneyWash.processor.prop) or `prop_laptop_01a`,
        formatTitle = function(rec)
            return ("[%s] Money Processor"):format(rec.id)
        end,
        formatDescription = function(rec)
            local heading = rec.heading or 0.0
            local x, y, z = rec.coords.x + 0.0, rec.coords.y + 0.0, rec.coords.z + 0.0
            return ("Coords: %.3f, %.3f, %.3f | Heading: %.1f"):format(x, y, z, heading + 0.0)
        end,
        getGizmoStartFromRecord = function(rec)
            local heading = rec.heading or 0.0
            return {
                coords = rec.coords,
                rotation = vector3(0.0, 0.0, heading),
            }
        end,
        toPayloadFromGizmo = function(gizmoResult, _existing)
            local heading = (gizmoResult.rotation and gizmoResult.rotation.z) or 0.0
            local pos = gizmoResult.position
            return {
                coords = { x = pos.x, y = pos.y, z = pos.z },
                heading = heading,
                data = {},
            }
        end,
    })
end)

-- NUI close
RegisterNUICallback("pmw_close", function(_, cb)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    cb({ ok = true })
end)

-- NUI -> client -> server bridges
local function safeCb(cb, payload)
    if cb then cb(payload or {}) end
end

RegisterNUICallback("pmw_processor_getState", function(data, cb)
    local processorId = data and (data.processorId or data.id)
    local res = lib.callback.await("pmw:processor:getState", false, tostring(processorId))
    safeCb(cb, res or { error = "no_state" })
end)

RegisterNUICallback("pmw_processor_unlockBusiness", function(data, cb)
    local processorId = data and (data.processorId or data.id)
    local businessId = data and (data.businessId or data.business_id)
    local res = lib.callback.await("pmw:processor:unlockBusiness", false, tostring(processorId), tostring(businessId))
    safeCb(cb, res or { error = "no_response" })
end)

RegisterNUICallback("pmw_processor_deposit", function(data, cb)
    local processorId = data and (data.processorId or data.id)
    local businessId = data and (data.businessId or data.business_id)
    local amount = data and data.amount
    local res = lib.callback.await("pmw:processor:deposit", false, tostring(processorId), tostring(businessId), tonumber(amount) or 0)
    safeCb(cb, res or { error = "no_response" })
end)

RegisterNUICallback("pmw_processor_withdraw", function(data, cb)
    local processorId = data and (data.processorId or data.id)
    local amount = data and data.amount
    local res = lib.callback.await("pmw:processor:withdraw", false, tostring(processorId), tonumber(amount) or 0)
    safeCb(cb, res or { error = "no_response" })
end)

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id, _ in pairs(MoneyProcessorInteractions) do
        RemoveMoneyProcessorInteraction(id)
    end
    for id, _ in pairs(RenderedMoneyProcessors) do
        UnrenderMoneyProcessor(id)
    end
    MoneyProcessors = {}
    RenderedMoneyProcessors = {}
    MoneyProcessorInteractions = {}
    MoneyProcessorEditing = {}
end)

