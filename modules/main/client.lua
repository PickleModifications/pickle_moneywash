Clubs = {}
LocalClubs = {}
RegisteredEntityTypes = {}
CurrentCamera = nil

function CreateScriptedCamera()
    if CurrentCamera then ExitScriptedCamera() end
    local initialCamSettings = {
        coords = GetGameplayCamCoord(),
        rotation = GetGameplayCamRot(),
        fov = GetGameplayCamFov(),
    }
    CurrentCamera = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", 
        initialCamSettings.coords.x, initialCamSettings.coords.y, initialCamSettings.coords.z, 
        initialCamSettings.rotation.x, initialCamSettings.rotation.y, initialCamSettings.rotation.z, initialCamSettings.fov
    )
    SetCamActive(CurrentCamera, true)
    RenderScriptCams(true, false, 0, true, true)
end

function ExitScriptedCamera(durationValue)
    local duration = durationValue
    if duration == nil then duration = 2000 end
    ClearFocus()
	DestroyAllCams()
    RenderScriptCams(false, true, duration, true, false) 
end


function RegisterClub(id, data)
    Clubs[id] = data
    local pcoords = GetEntityCoords(PlayerPedId())
    if #(pcoords - data.coords) < Config.RenderDistance then
        RenderClub(id)
    end
end

function UnregisterClub(id)
    UnrenderClub(id)
    Clubs[id] = nil
end

function RenderClub(id)
    UnrenderClub(id)
    local club = Clubs[id]
    if not club then return end
    LocalClubs[id] = {
        entities = {},
    }
    for k,v in pairs(club.entities) do
        LocalClubs[id].entities[k] = RenderClubEntity(id, k)
    end
end

function UnrenderClub(id)
    if not LocalClubs[id] then return end
    for k,v in pairs(LocalClubs[id].entities) do
        UnrenderClubEntity(id, k)
    end
    LocalClubs[id].entities = nil
    LocalClubs[id] = nil
end

function RenderClubEntity(id, entityId)
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    if not RegisteredEntityTypes[entity.type] then return end
    RegisteredEntityTypes[entity.type].onRender(id, entityId)
    return true
end

function UnrenderClubEntity(id, entityId)
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    if not RegisteredEntityTypes[entity.type] then return end
    RegisteredEntityTypes[entity.type].onUnrender(id, entityId)
end

function RegisterEntityType(entityType, data)
    RegisteredEntityTypes[entityType] = {
        label = data.label or entityType,
        description = data.description or "This is the " .. entityType .. " entity type.",
        data =  data.data or {},
        onRender = function(id, entityId)
            TriggerServerEvent("pickle_clubs:renderEntity", id, entityId)
            if data.onRender then
                data.onRender(id, entityId)
            end
        end,
        onUnrender = function(id, entityId)
            TriggerServerEvent("pickle_clubs:unrenderEntity", id, entityId)
            if data.onUnrender then
                data.onUnrender(id, entityId)
            end
        end,
    }
end

function UnregisterEntityType(entityType)
    RegisteredEntityTypes[entityType] = nil
end

function CreateClubNPC(pedId, coords, heading)
    local pedCfg = Config.Peds[pedId]
    local modelHash = `mp_m_freemode_01`
    if not pedCfg then 
        print("^1ERROR: No ped configuration found for: " .. pedId) 
    else 
        modelHash = pedCfg.model
    end
    local npc = CreateNPC(modelHash, coords.x, coords.y, coords.z, heading, false, true)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    FreezeEntityPosition(npc, true)
    return npc
end

local DialogContextCounter = 0

function StartClubPrompt(coords, heading, data)
    if not data or not data.dialog then return end
    -- Reset context counter for new prompt
    DialogContextCounter = 0
    CreateScriptedCamera()
    SetCamParams(CurrentCamera, coords.x, coords.y, coords.z + 0.5,
        0.0, 0.0, heading + 180.0, 90.0, 
        2000, 0, 0, 2
    )
    ShowDialogMenu(data.dialog)
end

function StopClubPrompt()
    ExitScriptedCamera()
    lib.hideContext()
end

function ShowDialogMenu(dialog, menuId)
    if not dialog then return end
    
    -- Call onStart callback if it exists
    if dialog.onStart then
        dialog.onStart()
    end
    
    DialogContextCounter = DialogContextCounter + 1
    local contextId = ('pickle_clubs_dialog_%s'):format(DialogContextCounter)
    local menuOptions = {}
    
    dialog.options = dialog.options or {}
    for i=1, #dialog.options do
        local option = dialog.options[i]
        local menuOption = {
            title = option.label,
            description = option.description or "",
            icon = option.icon,
        }
        
        -- If option has a nested dialog, create a submenu
        if option.dialog then
            menuOption.onSelect = function()
                -- Call option's onSelect callback if it exists before showing nested dialog
                if option.onSelect then
                    option.onSelect()
                end
                ShowDialogMenu(option.dialog, contextId)
            end
        else
            -- Leaf option - handle selection
            menuOption.onSelect = function()
                if option.onSelect then
                    option.onSelect()
                end
                -- If dialog should finish, close camera
                if dialog.finish then

                end
            end
        end
        
        table.insert(menuOptions, menuOption)
    end
    
    -- If dialog has finish=true and no options, add a default close option
    if dialog.finish then
        SetTimeout(2000, function()
            ExitScriptedCamera()
            lib.hideContext(contextId)
        end)
    end
    if dialog.speechSelect then
        dialog.speech = dialog.speechSelect()
    end
    -- Register and show context menu
    lib.registerContext({
        id = contextId,
        menu = menuId,
        title = dialog.speech or dialog.title or "Dialog",
        options = menuOptions
    })
    
    lib.showContext(contextId)
end

CreateThread(function()
    while true do
        for k,v in pairs(Clubs) do
            local pcoords = GetEntityCoords(PlayerPedId())
            local dist = #(pcoords - v.coords)
            if dist <= Config.RenderDistance and not LocalClubs[k] then
                RenderClub(k)
            elseif LocalClubs[k] and dist > Config.RenderDistance then
                UnrenderClub(k)
            end
        end
        Wait(1500)
    end
end)

AddEventHandler('onResourceStart', function(resource)
    Wait(1000)
    if resource == GetCurrentResourceName() then
        TriggerServerEvent("pickle_moneywash:initializePlayer")
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for k,v in pairs(Clubs) do
            UnregisterClub(k)
        end
    end
end)

RegisterNetEvent("pickle_clubs:syncClubs", function(id, data)
    if type(id) == "number" then
        if not data then return UnregisterClub(id) end
        RegisterClub(id, data)
    else 
        local data = id
        for k,v in pairs(Clubs) do
            UnregisterClub(k)
        end
        for k,v in pairs(data) do
            RegisterClub(k, v)
        end
    end
end)