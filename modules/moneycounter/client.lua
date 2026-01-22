local MONEYCOUNTER_DUI = {}
local MONEYCOUNTER_ENTITIES = {}
local MONEYCOUNTER_INTERACTION = nil
local MONEYBAG_AMOUNTS = {} -- Track amounts for each moneybag entity
local MoneyCounters = {} -- [id] = { id, coords, heading, ... }
local RenderedMoneyCounters = {} -- [id] = { moneycounter=entity, money=entity }
local MoneyCounterInteractions = {} -- [id] = interactionIndex (from CreateInteraction)
local MoneyCounterEditing = {} -- [id] = true while being moved via gizmo
local AnimatedBills = {} -- [id] = { [entity]=true }
local RemoteBillCounts = {} -- [id] = last bill count seen (for detecting new sessions)

local function DeleteAnimatedBills(id)
    print("^2Deleting animated bills for id: " .. id)
    id = tostring(id)
    if not AnimatedBills[id] then return end
    for ent, _ in pairs(AnimatedBills[id]) do
        if DoesEntityExist(ent) then
            DeleteEntity(ent)
        end
    end
    AnimatedBills[id] = nil
end

local function TrackAnimatedBill(id, ent)
    id = tostring(id)
    if not AnimatedBills[id] then AnimatedBills[id] = {} end
    AnimatedBills[id][ent] = true
end

local function GetMoneyCounterBaseEntity(id)
    id = tostring(id)
    if MONEYCOUNTER_INTERACTION and MONEYCOUNTER_INTERACTION.id == id and MONEYCOUNTER_INTERACTION.moneycounterEntity then
        return MONEYCOUNTER_INTERACTION.moneycounterEntity
    end
    if RenderedMoneyCounters[id] and RenderedMoneyCounters[id].moneycounter then
        return RenderedMoneyCounters[id].moneycounter
    end
    return nil
end

local function SpawnAnimatedBill(id, count, isLocalInteraction)
    id = tostring(id)
    local base = GetMoneyCounterBaseEntity(id)
    if not base or not DoesEntityExist(base) then return end

    local bill = CreateProp(`bkr_prop_money_unsorted_01`, 0.0, 0.0, 0.0, false, false, false)
    if not bill or bill == 0 then return end

    TrackAnimatedBill(id, bill)
    SetEntityCollision(bill, false, false)
    FreezeEntityPosition(bill, true)

    local progress = 0.0
    local billCount = tonumber(count) or 1

    -- Matches the old interactive animation offsets
    local start = {
        offsetCoords = vector3(0.0, 0.0, 0.25),
        offsetRotation = vector3(-90.0, 0.0, 0.0),
    }
    local finish = {
        offsetCoords = vector3(0.0, -0.17, 0.025 + ((billCount - 1) * 0.0025)),
        offsetRotation = vector3(0.0, 0.0, 0.0),
    }

    if isLocalInteraction and MONEYCOUNTER_INTERACTION then
        MONEYCOUNTER_INTERACTION.activeAnimations = (MONEYCOUNTER_INTERACTION.activeAnimations or 0) + 1
    end

    CreateThread(function()
        while DoesEntityExist(bill) do
            if progress < 1.0 then
                progress = progress + 0.02
                if progress > 1.0 then progress = 1.0 end
            end

            local offsetCoords = lerp(start.offsetCoords, finish.offsetCoords, progress)
            local offsetRotation = lerp(start.offsetRotation, finish.offsetRotation, progress)
            local baseCoords = GetOffsetFromEntityInWorldCoords(base, offsetCoords.x, offsetCoords.y, offsetCoords.z)
            local baseRotation = GetEntityRotation(base) + offsetRotation
            SetEntityCoords(bill, baseCoords.x, baseCoords.y, baseCoords.z)
            SetEntityRotation(bill, baseRotation.x, baseRotation.y, baseRotation.z, 2, true)

            if progress >= 1.0 then
                break
            end
            Wait(0)
        end

        -- Remote clients: keep bills in tray until session completes (same as local client)
        if not isLocalInteraction then
            -- Bill stays in tray; will be cleared when moneybag appears or session ends
            return
        end

        -- Local interaction: keep bill until we decide to clean up, but we still count completion.
        if MONEYCOUNTER_INTERACTION and MONEYCOUNTER_INTERACTION.id == id then
            MONEYCOUNTER_INTERACTION.activeAnimations = math.max((MONEYCOUNTER_INTERACTION.activeAnimations or 1) - 1, 0)
            if MONEYCOUNTER_INTERACTION.dirtyMoney <= 0 and not MONEYCOUNTER_INTERACTION.counted and (MONEYCOUNTER_INTERACTION.activeAnimations or 0) <= 0 then
                MONEYCOUNTER_INTERACTION.counted = true
                DeleteAnimatedBills(id)
                local moneybagEntity = CreateInteractiveEntity(
                    "moneybag",
                    MONEYCOUNTER_INTERACTION.moneycounterCoords + (MONEYCOUNTER_INTERACTION.interaction.forwardVector * -0.15),
                    MONEYCOUNTER_INTERACTION.heading,
                    {}
                )
                if moneybagEntity then
                    MONEYBAG_AMOUNTS[moneybagEntity] = MONEYCOUNTER_INTERACTION.originalDirtyMoney
                end
                if PMW_Sound3D and PMW_Sound3D.PlayNet then
                    PMW_Sound3D.PlayNet(MONEYCOUNTER_INTERACTION.coords, "audio/counter_done.mp3", { range = 35.0, volume = 0.85, playLocal = true })
                end
            end
        end
    end)
end

function CreateNamedRenderTargetForModel(name, model)
	local handle = 0
	if not IsNamedRendertargetRegistered(name) then
		RegisterNamedRendertarget(name, 0)
	end
	if not IsNamedRendertargetLinked(model) then
		LinkNamedRendertarget(model)
	end
	if IsNamedRendertargetRegistered(name) then
		handle = GetNamedRendertargetRenderId(name)
	end
	return handle
end

function RequestTextureDictionary(dict)
	RequestStreamedTextureDict(dict)
	while not HasStreamedTextureDictLoaded(dict) do Wait(0) end
	return dict
end

function LoadModel(model)
	if not IsModelInCdimage(model) then return end
	RequestModel(model)
	while not HasModelLoaded(model) do Wait(0) end
	return model
end

function RenderTarget(renderTarget, entity)
    SetTextRenderId(renderTarget) -- set render target
    Set_2dLayer(4)
    SetScriptGfxDrawBehindPausemenu(1)
    --DrawRect(0.5, 0.5, 1.0, 0.5, 255, 0, 0, 255); -- WOAH!
    local coords = GetEntityCoords(entity)
    local rot = GetEntityRotation(entity)
    DrawSprite("moneycounter_dict", "moneycounter_txd", 0.5, 0.5, 1.0, 1.0, 0.0, 255, 255, 255, 255)
    SetTextRenderId(GetDefaultScriptRendertargetRenderId()) -- reset
    SetScriptGfxDrawBehindPausemenu(0)
end

-- Function to clean up DUI
function CleanupMoneyCounterDUI()
    for entity, _ in pairs(MONEYCOUNTER_DUI) do
        if MONEYCOUNTER_DUI[entity].dui then
            DestroyDui(MONEYCOUNTER_DUI[entity].dui)
        end
        if MONEYCOUNTER_DUI[entity].duiProp then
            DeleteEntity(MONEYCOUNTER_DUI[entity].duiProp)
        end
    end
    MONEYCOUNTER_DUI = {}
end

-- Function to create DUI for money counter
local function CreateMoneyCounterDUI(entity)
    local resourceName = GetCurrentResourceName()
    local dui 
    duiUrl = "nui://" .. resourceName .. "/modules/moneycounter/dui/counter.html"
    print("^2Creating DUI with URL: " .. duiUrl)
    dui = CreateDui(duiUrl, 512, 256)
    
    if not dui then
        print("^1ERROR: Failed to create DUI for money counter with both methods")
        return nil
    end
    
    print("^2DUI created successfully, waiting for handle...")
    
    local attempts = 0
    local duiHandle = nil
    local maxAttempts = 100
    
    while attempts < maxAttempts do
        duiHandle = GetDuiHandle(dui)
        
        -- Handle can be a string or number, check both
        if duiHandle then
            local handleStr = tostring(duiHandle)
            if handleStr and handleStr ~= "" and handleStr ~= "0" and handleStr ~= "nil" then
                print("^2Got valid DUI handle: " .. handleStr)
                break
            end
        end
        
        Wait(100)
        attempts = attempts + 1
        
        -- Try sending a message to wake up the DUI
        if attempts % 10 == 0 then
            SendDuiMessage(dui, json.encode({type = "ping"}))
        end
    end
    
    if not duiHandle then
        print("^1ERROR: Failed to get DUI handle after " .. maxAttempts .. " attempts")
        DestroyDui(dui)
        return nil
    end
    
    local handleStr = tostring(duiHandle)
    if handleStr == "" or handleStr == "0" or handleStr == "nil" then
        print("^1ERROR: DUI handle is invalid: " .. handleStr)
        DestroyDui(dui)
        return nil
    end
    
    local txdName = "moneycounter_dict"
    local txd = CreateRuntimeTxd(txdName)
    local tx = CreateRuntimeTextureFromDuiHandle(txd, 'moneycounter_txd', duiHandle)
    local coords = GetOffsetFromEntityInWorldCoords(entity, -0.07, -0.022, 0.269)
    print("^2Creating prop at coords: " .. coords.x .. ", " .. coords.y .. ", " .. coords.z)
    local duiProp = CreateProp(`hei_prop_hei_monitor_overlay`, coords.x, coords.y, coords.z, false, false, false)
    FreezeEntityPosition(duiProp, true)
    SetEntityRotation(duiProp, -30.0, 0.0, GetEntityHeading(entity), 2, true)
    -- Use pcall to catch any errors
    print("^2Creating runtime texture with name: " .. txdName .. ", handle: " .. handleStr)
    local id = CreateNamedRenderTargetForModel("hei_mon", `hei_prop_hei_monitor_overlay`)
    RenderTarget(id, duiProp)

    print("^2Created render target with ID: ", id, duiProp)
    local forwardVector, rightVector, upVector, position = GetEntityMatrix(duiProp)
    SetEntityCollision(duiProp, false, false)
    MONEYCOUNTER_DUI[entity] = {
        dui = dui,
        duiHandle = duiHandle,
        txd = txd,
        tx = tx,
        txdName = txdName,
        counterValue = 0,
        id = id,
        duiProp = duiProp,
        matrix = {
            forwardVector = forwardVector,
            rightVector = rightVector,
            upVector = upVector,
            position = position,
        },
    }
    
    return MONEYCOUNTER_DUI[entity]
end

-- Function to update counter value
function UpdateMoneyCounter(entity, value)
    if not MONEYCOUNTER_DUI[entity] then return end
    
    local duiData = MONEYCOUNTER_DUI[entity]
    duiData.counterValue = value or 0
    
    SendDuiMessage(duiData.dui, json.encode({
        type = "setCounter",
        value = duiData.counterValue
    }))
end

-- Function to add to counter value
function AddMoneyCounter(entity, amount)
    if not MONEYCOUNTER_DUI[entity] then return end
    
    local duiData = MONEYCOUNTER_DUI[entity]
    duiData.counterValue = (duiData.counterValue or 0) + (amount or 0)
    
    SendDuiMessage(duiData.dui, json.encode({
        type = "addCounter",
        value = math.floor(amount)
    }))
end

function SetMoneyCounter(entity, amount)
    if not MONEYCOUNTER_DUI[entity] then return end
    local duiData = MONEYCOUNTER_DUI[entity]
    duiData.counterValue = amount
    SendDuiMessage(duiData.dui, json.encode({
        type = "setCounter",
        value = duiData.counterValue
    }))
end

-- Function to reset counter
function ResetMoneyCounter(entity)
    if not MONEYCOUNTER_DUI[entity] then return end
    
    local duiData = MONEYCOUNTER_DUI[entity]
    duiData.counterValue = 0
    
    SendDuiMessage(duiData.dui, json.encode({
        type = "resetCounter"
    }))
end

-- Function to get all moneycounter entities
function GetMoneyCounterEntities()
    local entities = {}
    for entity, _ in pairs(MONEYCOUNTER_ENTITIES) do
        if DoesEntityExist(entity) then
            entities[#entities + 1] = entity
        end
    end
    return entities
end

function UnrenderMoneyCounter(id)
    if not RenderedMoneyCounters[id] then return end
    if RenderedMoneyCounters[id].moneycounter then
        DeleteEntity(RenderedMoneyCounters[id].moneycounter)
    end
    if RenderedMoneyCounters[id].money then
        DeleteEntity(RenderedMoneyCounters[id].money)
    end
    RenderedMoneyCounters[id] = nil
    DeleteAnimatedBills(id)
    -- Clear remote bill tracking when counter is unrendered
    RemoteBillCounts[id] = nil
end

function RenderMoneyCounter(id)
    UnrenderMoneyCounter(id)
    local moneyCounter = MoneyCounters[id]
    if not moneyCounter then return end
    if CURRENT_INTERACTION then return end
    RenderedMoneyCounters[id] = {} -- prevents double rendering
    local coords = moneyCounter.coords
    local heading = moneyCounter.heading
    local temp = CreateTennisBall(coords.x, coords.y, coords.z)
    SetEntityRotation(temp, 0.0, 0.0, heading, 2, true)
    local forwardVector, rightVector, upVector, position = GetEntityMatrix(temp)
    DeleteEntity(temp)
    local moneycounterCoords = coords + (rightVector * -0.35)
    local moneycounter = CreateProp(`bkr_prop_money_counter`, moneycounterCoords.x, moneycounterCoords.y, moneycounterCoords.z, false, false, false)
    SetEntityCollision(moneycounter, true, true)
    SetEntityHeading(moneycounter, heading)
    local moneyCoords = coords + (rightVector * 0.35)
    local money = CreateProp(`bkr_prop_money_unsorted_01`, moneyCoords.x, moneyCoords.y, moneyCoords.z, false, false, false)
    SetEntityCollision(money, true, true)
    SetEntityHeading(money, heading)
    RenderedMoneyCounters[id] = {
        moneycounter = moneycounter,
        money = money,
    }
end

-- Export functions for use in other scripts
exports('UpdateMoneyCounter', UpdateMoneyCounter)
exports('AddMoneyCounter', AddMoneyCounter)
exports('ResetMoneyCounter', ResetMoneyCounter)
exports('GetMoneyCounterEntities', GetMoneyCounterEntities)

function StopMoneyCounterInteraction(id)
    CleanupMoneyCounterDUI()
    StopInteraction()
    ClearPedTasks(PlayerPedId())
    RenderMoneyCounter(id)
    DeleteAnimatedBills(id)
    -- Release the exclusive-use lock server-side
    if id then
        TriggerServerEvent("pickle_moneywash:moneycounter:releaseUse", tostring(id))
    end
    MONEYCOUNTER_INTERACTION = nil
end

function StartMoneyCounterInteraction(id) 
    -- Remove up to the allowed maximum from dirtyMoney for this counting session
    if not MONEYCOUNTER_INTERACTION then return end
    local interaction = MONEYCOUNTER_INTERACTION.interaction
    local coords = MONEYCOUNTER_INTERACTION.coords
    local heading = MONEYCOUNTER_INTERACTION.heading
    local moneycounterCoords = MONEYCOUNTER_INTERACTION.moneycounterCoords
    local moneycounterEntity = MONEYCOUNTER_INTERACTION.moneycounterEntity
    local maxAmount = Config.MoneyCounter.maxCountAmount or 10000
    local dirtyMoney = MONEYCOUNTER_INTERACTION.totalDirtyMoney or 0

    if dirtyMoney <= 0 then
        StopMoneyCounterInteraction(id)
        return
    end

    local countAmount = math.min(dirtyMoney, maxAmount)
    MONEYCOUNTER_INTERACTION.counted = false
    MONEYCOUNTER_INTERACTION.originalDirtyMoney = countAmount
    MONEYCOUNTER_INTERACTION.dirtyMoney = countAmount
    MONEYCOUNTER_INTERACTION.totalDirtyMoney = dirtyMoney - countAmount
    local moneyPerBill = MONEYCOUNTER_INTERACTION.dirtyMoney / MONEYCOUNTER_INTERACTION.billAmount

    ShowNotification(_L("moneycounter_place_money", GetCurrencyString(countAmount)))
    for i=1, MONEYCOUNTER_INTERACTION.billAmount do 
        CreateInteractiveEntity("money", coords + (interaction.rightVector * 0.35), heading, {})
    end

    -- Example: Set initial counter value (you can remove this or modify as needed)
    -- if moneycounterEntity then
    --     Wait(500) -- Wait for DUI to be created
    --     UpdateMoneyCounter(moneycounterEntity, 0)
    -- end
    local minimum, maximum = GetModelDimensions(`bkr_prop_money_counter`)
    local width = maximum.y - minimum.y
    local height = maximum.z - minimum.z
    -- Spawn position for money (where remaining money text will be shown)
    local spawnPosition = coords + (interaction.rightVector * 0.35)
    local movedEntities = {} -- Track entities that have moved from spawn position
    local movedBills = 0
    CreateThread(function()
        while MONEYCOUNTER_INTERACTION and not MONEYCOUNTER_INTERACTION.done do            
            -- Draw 3D text at spawn position showing remaining money
            local remainingMoney = countAmount * (1 - (movedBills / MONEYCOUNTER_INTERACTION.billAmount))
            if remainingMoney > 0 then
                DrawText3D(spawnPosition.x, spawnPosition.y, spawnPosition.z + 0.15, _L("moneycounter_remaining", GetCurrencyString(math.floor(remainingMoney))))
            end
            
            -- Collect entities to delete first to avoid modifying table during iteration
            local entitiesToDelete = {}
            for k,v in pairs(INT_ENTITIES) do
                -- Draw 3D text on moneybag entities
                if v.type == "moneybag" and DrawText3D and MONEYBAG_AMOUNTS[k] then
                    local entityCoords = GetEntityCoords(k)
                    local amount = MONEYBAG_AMOUNTS[k]
                    DrawText3D(entityCoords.x, entityCoords.y, entityCoords.z + 0.15, _L("moneybag_collect", GetCurrencyString(math.floor(amount))))
                end
                
                if v.type == "money" then
                    local entityCoords = GetEntityCoords(k)
                    local distanceFromSpawn = #(entityCoords - spawnPosition)
                    
                    -- Check if entity has moved from spawn position (threshold: 0.1 units)
                    if distanceFromSpawn > 0.00001 and not movedEntities[k] then
                        -- Deduct money when entity is first moved from spawn position
                        movedEntities[k] = true -- Mark as moved so we don't deduct again
                        movedBills = movedBills + 1
                    end
                    
                    -- Draw 3D text on money entity showing moneyPerBill once it's moved from spawn position
                    if movedEntities[k] and moneyPerBill > 0 then
                        DrawText3D(entityCoords.x, entityCoords.y, entityCoords.z + 0.1, ("%s"):format(GetCurrencyString(math.floor(moneyPerBill))))
                    end
                    local offset = GetOffsetFromEntityGivenWorldCoords(moneycounterEntity, entityCoords.x, entityCoords.y, entityCoords.z)
                    if offset.x > -0.4 and offset.x < 0.16 and entityCoords.z < moneycounterCoords.z + (height - 0.1) + 0.1 then
                        MONEYCOUNTER_INTERACTION.dirtyMoney = MONEYCOUNTER_INTERACTION.dirtyMoney - moneyPerBill
                        entitiesToDelete[#entitiesToDelete + 1] = k
                        -- Spawn local animated bill + broadcast to nearby clients
                        SpawnAnimatedBill(id, movedBills, true)
                        TriggerServerEvent("pickle_moneywash:moneycounter:billInserted", id, movedBills)
                        if PMW_Sound3D and PMW_Sound3D.PlayNet then
                            PMW_Sound3D.PlayNet(MONEYCOUNTER_INTERACTION.coords, "audio/counter_processing.mp3", { range = 25.0, volume = 0.7, playLocal = true })
                        end
                        AddMoneyCounter(moneycounterEntity, moneyPerBill)
                        if MONEYCOUNTER_INTERACTION.dirtyMoney <= 0 then
                            SetMoneyCounter(MONEYCOUNTER_INTERACTION.moneycounterEntity, MONEYCOUNTER_INTERACTION.originalDirtyMoney)
                        end        
                        -- Clean up moved entity tracking when deleted
                        movedEntities[k] = nil
                    end
                end
            end
            
            -- Delete entities after iteration is complete
            for i = 1, #entitiesToDelete do
                DeleteInteractiveEntity(entitiesToDelete[i])
            end
            
            Wait(10)
        end
        if not MONEYCOUNTER_INTERACTION then return end
        MONEYCOUNTER_INTERACTION.done = false
        SetMoneyCounter(moneycounterEntity, 0)
    local data = lib.callback.await("pickle_moneywash:countMoney", false, id)
    if not data then return StopMoneyCounterInteraction(id) end
        print("^2Data: ", json.encode(data))
        if data.totalDirtyMoney <= 0 then
            return StopMoneyCounterInteraction(id)
        end
        if not MONEYCOUNTER_INTERACTION then return end
        MONEYCOUNTER_INTERACTION.totalDirtyMoney = data.totalDirtyMoney
        StartMoneyCounterInteraction(id)
    end)
end

function InitializeMoneyCounterInteraction(id)
    local moneyCounter = MoneyCounters[id]
    if not moneyCounter then return end
    -- Acquire exclusive-use lock (one player per entity)
    local lock = lib.callback.await("pickle_moneywash:moneycounter:tryUse", false, id)
    if not lock or lock.ok ~= true then
        ShowNotification(_L("moneycounter_in_use") or "Someone is already using this money counter.")
        return
    end
    local data = lib.callback.await("pickle_moneywash:getMoneyCounterData", false, id)
    if not data then return end
    if data.totalDirtyMoney <= 0 then return ShowNotification(_L("moneycounter_no_dirty_money")) end
    UnrenderMoneyCounter(id)
    local coords = moneyCounter.coords
    local heading = moneyCounter.heading
    -- Clean up any existing DUI before creating a new one
    CleanupMoneyCounterDUI()
    
    MONEYCOUNTER_INTERACTION = {
        id = id,
        coords = coords,
        heading = heading,
        totalDirtyMoney = data.totalDirtyMoney,
        billAmount = Config.MoneyCounter.billAmount or 5,
    }
    local interaction = StartInteraction(coords, heading)
    local moneycounterCoords = coords + (interaction.rightVector * -0.35)
    local moneycounterEntity = CreateInteractiveEntity("moneycounter", moneycounterCoords, heading, {})
    CreateThread(function()
        local scale = vector3(0.25, 0.175, 0.0)
        while MONEYCOUNTER_INTERACTION do
            SetEntityLocallyInvisible(PlayerPedId(), true)
            DisableControlAction(1, 202, true)
            for k,v in pairs(MONEYCOUNTER_DUI) do
                RenderTarget(v.id, v.duiProp)
                local matrix = v.matrix
                SetEntityMatrix(v.duiProp, matrix.forwardVector, matrix.rightVector * scale.x, matrix.upVector * scale.y, matrix.position)
            end
            if IsDisabledControlJustPressed(1, 202) then
                StopMoneyCounterInteraction(id)
            end
            Wait(0)
        end
    end)

    -- Keepalive + proximity watchdog: auto-release if player leaves the area
    CreateThread(function()
        local validateDistance = 5.0
        while MONEYCOUNTER_INTERACTION and MONEYCOUNTER_INTERACTION.id == id do
            local ped = PlayerPedId()
            local pcoords = GetEntityCoords(ped)
            local dist = #(pcoords - coords)
            if dist > validateDistance then
                ShowNotification(_L("moneycounter_too_far") or "You moved too far away from the money counter.")
                StopMoneyCounterInteraction(id)
                break
            end
            TriggerServerEvent("pickle_moneywash:moneycounter:keepalive", tostring(id))
            Wait(5000)
        end
    end)
    PlayAnim(PlayerPedId(), "amb@prop_human_bum_shopping_cart@male@idle_a", "idle_c", 8.0, -8.0, -1, 1, 0, 0, 0, 0)
    -- Create DUI for the moneycounter entity now that interaction has started
    if moneycounterEntity then
        CreateMoneyCounterDUI(moneycounterEntity)
    end
    
    MONEYCOUNTER_INTERACTION.moneycounterCoords = moneycounterCoords
    MONEYCOUNTER_INTERACTION.moneycounterEntity = moneycounterEntity
    MONEYCOUNTER_INTERACTION.interaction = interaction
    StartMoneyCounterInteraction(id)
end

CreateThread(function()
    Wait(1000)
    RegisterInteractiveEntity("moneycounter", {
        init = function(coords, heading, data, params)
            local moneycounter = CreateProp(`bkr_prop_money_counter`, coords.x, coords.y, coords.z, false, false, false)
            SetEntityCollision(moneycounter, true, true)
            SetEntityHeading(moneycounter, heading)
            
            MONEYCOUNTER_ENTITIES[moneycounter] = true
            
            return moneycounter, {
                disableInteraction = true,
                disableGravity = true,
            }
        end,
    })
    RegisterInteractiveEntity("money", {
        init = function(coords, heading, data, params)
            local moneycounter = CreateProp(`bkr_prop_money_unsorted_01`, coords.x, coords.y, coords.z, false, false, false)
            SetEntityCollision(moneycounter, true, true)
            SetEntityHeading(moneycounter, heading)
            return moneycounter, {
                heightOffset = 0.275,
            }
        end,
    })
    RegisterInteractiveEntity("moneybag", {
        init = function(coords, heading, data, params)
            local moneycounter = CreateProp(`prop_poly_bag_money`, coords.x, coords.y, coords.z, false, false, false)
            SetEntityCollision(moneycounter, true, true)
            SetEntityHeading(moneycounter, heading)
            
            -- For remote clients: clear bills when moneybag appears (session completed)
            -- Check if this moneybag is near any money counter and clear bills for that counter
            if not MONEYCOUNTER_INTERACTION then
                for counterId, counterData in pairs(MoneyCounters) do
                    if counterData and counterData.coords then
                        local dist = #(coords - counterData.coords)
                        -- Moneybag appears ~0.15 units from counter, so check within 1.0 units
                        if dist <= 1.0 then
                            DeleteAnimatedBills(counterId)
                            RemoteBillCounts[counterId] = nil -- Reset tracking for next session
                            break
                        end
                    end
                end
            end
            
            return moneycounter, {
                heightOffset = 0.275,
            }
        end,
        selectedThread = function(entity, data)
            -- Clean up amount tracking when moneybag is deleted
            MONEYBAG_AMOUNTS[entity] = nil
            DeleteInteractiveEntity(entity)
            MONEYCOUNTER_INTERACTION.done = true
        end,
    })

    -- InitializeMoneyCounterInteraction(coords, heading)
end)

RegisterNetEvent("pickle_moneywash:initializePlayer", function(data)
    MoneyCounters = {}
    local list = (data and data.moneyCounters) or {}
    for i = 1, #list do
        local rec = list[i]
        if rec and rec.id and rec.coords then
            MoneyCounters[tostring(rec.id)] = rec
        end
    end
end)

local function EnsureMoneyCounterInteraction(id)
    local moneyCounter = MoneyCounters[id]
    if not moneyCounter then return end
    if MoneyCounterInteractions[id] then return end
    MoneyCounterInteractions[id] = CreateInteraction({
        coords = moneyCounter.coords,
        heading = moneyCounter.heading,
        label = "Money Counter",
        icon = Config.TargetIcons.moneycounter,
    }, function()
        local canManage = lib.callback.await("pickle_moneywash:entities:canManage", false, "moneycounter", id) == true
        if canManage then
            -- Prefer a simple confirm dialog if available; fallback to a context menu prompt.
            local ok, res = pcall(function()
                return lib.alertDialog({
                    header = "Manage",
                    content = "Manage this money counter?",
                    centered = true,
                    cancel = true,
                    labels = { confirm = "Yes", cancel = "No" },
                })
            end)

            if ok then
                if res == "confirm" then
                    TriggerEvent("pickle_moneywash:entities:openManage", "moneycounter", id)
                    return
                end
                -- res == "cancel" => fall through to normal interaction
            else
                local promptId = ("pmw_manage_prompt_moneycounter_%s"):format(id)
                lib.registerContext({
                    id = promptId,
                    title = "Manage",
                    options = {
                        {
                            title = "Manage",
                            onSelect = function()
                                TriggerEvent("pickle_moneywash:entities:openManage", "moneycounter", id)
                            end,
                        },
                        {
                            title = "Use money counter",
                            onSelect = function()
                                InitializeMoneyCounterInteraction(id)
                            end,
                        },
                    },
                })
                lib.showContext(promptId)
                return
            end
        end

        InitializeMoneyCounterInteraction(id)
    end)
end

local function RemoveMoneyCounterInteraction(id)
    if not MoneyCounterInteractions[id] then return end
    DeleteInteraction(MoneyCounterInteractions[id])
    MoneyCounterInteractions[id] = nil
end

-- Keep money counters rendered/interactive as you move around
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        for id, moneyCounter in pairs(MoneyCounters) do
            if MoneyCounterEditing[id] then
                -- Don't render or interact while the entity is being repositioned
                RemoveMoneyCounterInteraction(id)
                UnrenderMoneyCounter(id)
                goto continue
            end
            local dist = #(pcoords - moneyCounter.coords)
            if dist <= Config.RenderDistance then
                EnsureMoneyCounterInteraction(id)
                if not RenderedMoneyCounters[id] then
                    RenderMoneyCounter(id)
                end
            else
                if MONEYCOUNTER_INTERACTION and MONEYCOUNTER_INTERACTION.id == id then
                    -- Don't tear down while actively using it
                else
                    RemoveMoneyCounterInteraction(id)
                    UnrenderMoneyCounter(id)
                end
            end
            ::continue::
        end
        Wait(1500)
    end
end)

-- React to dynamic entity changes (created/updated/deleted in-game)
RegisterNetEvent("pickle_moneywash:entities:syncAll", function(snapshot)
    local bucket = snapshot and snapshot.moneycounter or {}
    MoneyCounters = {}
    for id, rec in pairs(bucket) do
        if rec and rec.coords then
            MoneyCounters[tostring(id)] = rec
        end
    end
end)

RegisterNetEvent("pickle_moneywash:entities:changed", function(action, entityType, id, record)
    if tostring(entityType) ~= "moneycounter" then return end
    id = tostring(id)

    if action == "delete" then
        RemoveMoneyCounterInteraction(id)
        UnrenderMoneyCounter(id)
        MoneyCounters[id] = nil
        return
    end

    if action == "create" or action == "update" then
        if record and record.coords then
            MoneyCounters[id] = record
            -- Force refresh any existing world state to match new coords/heading
            RemoveMoneyCounterInteraction(id)
            UnrenderMoneyCounter(id)
        end
    end
end)

-- Bill animation broadcast from server (other players' counting sessions)
RegisterNetEvent("pickle_moneywash:moneycounter:billInserted", function(moneyCounterId, record, count)
    local id = tostring(moneyCounterId)
    -- Best-effort: ensure we have the entity info locally
    if not MoneyCounters[id] and type(record) == "table" and record.coords then
        MoneyCounters[id] = {
            id = id,
            coords = record.coords,
            heading = record.heading or 0.0,
            data = record.data,
        }
    end

    -- Only show if this client currently has the counter rendered (i.e., in range)
    if not RenderedMoneyCounters[id] or not RenderedMoneyCounters[id].moneycounter then return end
    
    -- For remote clients: if bill count resets to 1, it's a new session - clear old bills
    local billCount = tonumber(count) or 1
    if not MONEYCOUNTER_INTERACTION or MONEYCOUNTER_INTERACTION.id ~= id then
        local lastCount = RemoteBillCounts[id] or 0
        if billCount == 1 and lastCount > 1 then
            -- New session started, clear old bills
            DeleteAnimatedBills(id)
        end
        RemoteBillCounts[id] = billCount
    end
    
    SpawnAnimatedBill(id, count, false)
end)

-- Session ended event: clear bills when executing client stops using the counter
RegisterNetEvent("pickle_moneywash:moneycounter:sessionEnded", function(moneyCounterId)
    local id = tostring(moneyCounterId)
    -- Only clear if we're not the executing client (they handle their own cleanup)
    if not MONEYCOUNTER_INTERACTION or MONEYCOUNTER_INTERACTION.id ~= id then
        DeleteAnimatedBills(id)
        RemoteBillCounts[id] = nil -- Reset tracking for next session
    end
end)

-- Temporarily hide while an admin is repositioning via gizmo
AddEventHandler("pickle_moneywash:entities:editStart", function(entityType, id)
    if tostring(entityType) ~= "moneycounter" then return end
    id = tostring(id)
    MoneyCounterEditing[id] = true
    RemoveMoneyCounterInteraction(id)
    UnrenderMoneyCounter(id)
end)

AddEventHandler("pickle_moneywash:entities:editEnd", function(entityType, id)
    if tostring(entityType) ~= "moneycounter" then return end
    id = tostring(id)
    MoneyCounterEditing[id] = nil
    -- Renderer thread will restore when in range; force quick refresh for responsiveness
    RemoveMoneyCounterInteraction(id)
    UnrenderMoneyCounter(id)
end)

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        if MONEYCOUNTER_INTERACTION and MONEYCOUNTER_INTERACTION.id then
            TriggerServerEvent("pickle_moneywash:moneycounter:releaseUse", tostring(MONEYCOUNTER_INTERACTION.id))
        end
        for entity, _ in pairs(MONEYCOUNTER_DUI) do
            if MONEYCOUNTER_DUI[entity].dui then
                DestroyDui(MONEYCOUNTER_DUI[entity].dui)
            end
            if MONEYCOUNTER_DUI[entity].duiProp then
                DeleteEntity(MONEYCOUNTER_DUI[entity].duiProp)
            end
        end
        for k,v in pairs(RenderedMoneyCounters) do
            UnrenderMoneyCounter(k)
        end
        for id, interactionId in pairs(MoneyCounterInteractions) do
            RemoveMoneyCounterInteraction(id)
        end
        for id, _ in pairs(AnimatedBills) do
            DeleteAnimatedBills(id)
        end
        MONEYCOUNTER_DUI = {}
        MONEYCOUNTER_ENTITIES = {}
        MONEYBAG_AMOUNTS = {}
        MoneyCounters = {}
        RenderedMoneyCounters = {}
        MoneyCounterInteractions = {}
        MoneyCounterEditing = {}
    end
end)