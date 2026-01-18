local MONEYCOUNTER_DUI = {}
local MONEYCOUNTER_ENTITIES = {}
local MONEYCOUNTER_INTERACTION = nil
local MONEYBAG_AMOUNTS = {} -- Track amounts for each moneybag entity
local MoneyCounters = {}
local RenderedMoneyCounters = {}

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

function UnrenderMoneyCounter(index)
    if not RenderedMoneyCounters[index] then return end
    if RenderedMoneyCounters[index].moneycounter then
        DeleteEntity(RenderedMoneyCounters[index].moneycounter)
    end
    if RenderedMoneyCounters[index].money then
        DeleteEntity(RenderedMoneyCounters[index].money)
    end
    RenderedMoneyCounters[index] = nil
end

function RenderMoneyCounter(index)
    UnrenderMoneyCounter(index)
    local moneyCounter = MoneyCounters[index]
    if not moneyCounter then return end
    if CURRENT_INTERACTION then return end
    RenderedMoneyCounters[index] = {} -- prevents double rendering
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
    local money = CreateProp(`bkr_prop_money_wrapped_01`, moneyCoords.x, moneyCoords.y, moneyCoords.z, false, false, false)
    SetEntityCollision(money, true, true)
    SetEntityHeading(money, heading)
    RenderedMoneyCounters[index] = {
        moneycounter = moneycounter,
        money = money,
    }
end

-- Export functions for use in other scripts
exports('UpdateMoneyCounter', UpdateMoneyCounter)
exports('AddMoneyCounter', AddMoneyCounter)
exports('ResetMoneyCounter', ResetMoneyCounter)
exports('GetMoneyCounterEntities', GetMoneyCounterEntities)

function StopMoneyCounterInteraction(index)
    ShowNotification(_L("moneycounter_no_dirty_money"))
    CleanupMoneyCounterDUI()
    StopInteraction()
    ClearPedTasks(PlayerPedId())
    RenderMoneyCounter(index)
    MONEYCOUNTER_INTERACTION = nil
end

function StartMoneyCounterInteraction(index) 
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
        StopMoneyCounterInteraction(index)
        return
    end

    local countAmount = math.min(dirtyMoney, maxAmount)
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
    local leftBound = GetOffsetFromEntityInWorldCoords(moneycounterEntity, 0.16, 0.0, 0.0).x
    local rightBound = GetOffsetFromEntityInWorldCoords(moneycounterEntity, -0.38, 0.0, 0.0).x

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
                    DrawText3D(entityCoords.x, entityCoords.y, entityCoords.z + 0.15, _L("moneybag_withdraw", GetCurrencyString(math.floor(amount))))
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
                    
                    -- Check if money is in counter bounds
                    if entityCoords.x > leftBound and entityCoords.x < rightBound and entityCoords.z < moneycounterCoords.z + (height - 0.1) + 0.1 then
                        MONEYCOUNTER_INTERACTION.dirtyMoney = MONEYCOUNTER_INTERACTION.dirtyMoney - moneyPerBill
                        entitiesToDelete[#entitiesToDelete + 1] = k
                        AddMoneyCounter(moneycounterEntity, moneyPerBill)
                        -- Clean up moved entity tracking when deleted
                        movedEntities[k] = nil
                        if MONEYCOUNTER_INTERACTION.dirtyMoney <= 0 then
                            SetMoneyCounter(moneycounterEntity, countAmount)
                            local moneybagEntity = CreateInteractiveEntity("moneybag", moneycounterCoords + (interaction.forwardVector * -0.15), heading, {})
                            -- Store the amount for this moneybag
                            if moneybagEntity then
                                MONEYBAG_AMOUNTS[moneybagEntity] = countAmount
                            end
                        end
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
        local data = lib.callback.await("pickle_moneywash:washMoney", false, index)
        if not data then return StopMoneyCounterInteraction(index) end
        print("^2Data: ", json.encode(data))
        if data.totalDirtyMoney <= 0 then
            ShowNotification(_L("moneycounter_no_dirty_money"))
            return StopMoneyCounterInteraction(index)
        end
        MONEYCOUNTER_INTERACTION.totalDirtyMoney = data.totalDirtyMoney
        StartMoneyCounterInteraction(index)
    end)
end

function InitializeMoneyCounterInteraction(index)
    local moneyCounter = MoneyCounters[index]
    if not moneyCounter then return end
    local data = lib.callback.await("pickle_moneywash:getMoneyCounterData", false, index)
    if not data then return end
    if data.totalDirtyMoney <= 0 then return ShowNotification(_L("moneycounter_no_dirty_money")) end
    UnrenderMoneyCounter(index)
    local coords = moneyCounter.coords
    local heading = moneyCounter.heading
    -- Clean up any existing DUI before creating a new one
    CleanupMoneyCounterDUI()
    
    MONEYCOUNTER_INTERACTION = {
        coords = coords,
        heading = heading,
        totalDirtyMoney = data.totalDirtyMoney,
        billAmount = Config.MoneyCounter.billAmount or 5,
    }
    local interaction = StartInteraction(coords, heading)
    local moneycounterCoords = coords + (interaction.rightVector * -0.35)
    local moneycounterEntity = CreateInteractiveEntity("moneycounter", moneycounterCoords, heading, {})
    CreateThread(function()
        SetEntityVisible(PlayerPedId(), false, false)
        local scale = vector3(0.25, 0.175, 0.0)
        while MONEYCOUNTER_INTERACTION do
            DisableControlAction(1, 202, true)
            for k,v in pairs(MONEYCOUNTER_DUI) do
                RenderTarget(v.id, v.duiProp)
                local matrix = v.matrix
                SetEntityMatrix(v.duiProp, matrix.forwardVector, matrix.rightVector * scale.x, matrix.upVector * scale.y, matrix.position)
            end
            if IsDisabledControlJustPressed(1, 202) then
                StopMoneyCounterInteraction(index)
            end
            Wait(0)
        end
        SetEntityVisible(PlayerPedId(), true, false)
    end)
    PlayAnim(PlayerPedId(), "amb@prop_human_bum_shopping_cart@male@idle_a", "idle_c", 8.0, -8.0, -1, 1, 0, 0, 0, 0)
    -- Create DUI for the moneycounter entity now that interaction has started
    if moneycounterEntity then
        CreateMoneyCounterDUI(moneycounterEntity)
    end
    
    MONEYCOUNTER_INTERACTION.moneycounterCoords = moneycounterCoords
    MONEYCOUNTER_INTERACTION.moneycounterEntity = moneycounterEntity
    MONEYCOUNTER_INTERACTION.interaction = interaction
    StartMoneyCounterInteraction(index)
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
            local moneycounter = CreateProp(`bkr_prop_money_wrapped_01`, coords.x, coords.y, coords.z, false, false, false)
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
    MoneyCounters = data.moneyCounters
    local pcoords = GetEntityCoords(PlayerPedId())
    for i=1, #MoneyCounters do
        local moneyCounter = MoneyCounters[i]
        if #(pcoords - moneyCounter.coords) < Config.RenderDistance then
            RenderMoneyCounter(i)
            CreateInteraction({
                coords = moneyCounter.coords,
                heading = moneyCounter.heading,
                label = "Money Counter",
                icon = Config.TargetIcons.moneycounter,
            }, function()
                InitializeMoneyCounterInteraction(i)
            end)
        end
    end
end)

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
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
        MONEYCOUNTER_DUI = {}
        MONEYCOUNTER_ENTITIES = {}
        MONEYBAG_AMOUNTS = {}
    end
end)