Clubs = {}
RegisteredEntityTypes = {}
EntityPlayers = {}

function RegisterClub(data, skipSync)
    Clubs[data.id] = {
        label = data.label,
        description = data.description,
        coords = data.coords,
        entities = data.entities,
    }
    for k,v in pairs(data.entities) do
        StartClubEntity(data.id, k)
    end
    if not skipSync then
        TriggerClientEvent("pickle_clubs:syncClubs", -1, Clubs)
    end
end

function StartClubEntity(id, entityId)
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    if not RegisteredEntityTypes[entity.type] then return end
    RegisteredEntityTypes[entity.type].onStart(id, entityId)
end

function StopClubEntity(id, entityId)
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    if not RegisteredEntityTypes[entity.type] then return end
    RegisteredEntityTypes[entity.type].onStop(id, entityId)
end

function RegisterEntityType(entityType, data)
    RegisteredEntityTypes[entityType] = {
        label = data.label or entityType,
        description = data.description or "This is the " .. entityType .. " entity type.",
        data =  data.data or {},
        onStart = data.onStart or (function(data)
            print("ERROR: No onStart callback for entity type: " .. entityType)
        end),
        onRender = data.onRender or (function(data)
            print("ERROR: No onRender callback for entity type: " .. entityType)
        end),
        onUnrender = data.onUnrender or (function(data)
            print("ERROR: No onUnrender callback for entity type: " .. entityType)
        end),
        onStop = data.onStop or (function()
            print("ERROR: No onStop callback for entity type: " .. entityType)
        end),
    }
end

function UnregisterEntityType(entityType)
    RegisteredEntityTypes[entityType] = nil
end

function TriggerEntityEvent(event, id, entityId, ...)
    if not EntityPlayers[id] or not EntityPlayers[id][entityId] then return end
    for i=1, #EntityPlayers[id][entityId] do
        local player = EntityPlayers[id][entityId][i]
        TriggerClientEvent(event, player, id, entityId, ...)
    end
end

RegisterNetEvent("pickle_clubs:renderEntity", function(id, entityId, ...)
    local source = source
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    if not RegisteredEntityTypes[entity.type] then return end
    RegisteredEntityTypes[entity.type].onRender(id, entityId, source, ...)
    if not EntityPlayers[id] then EntityPlayers[id] = {} end
    if not EntityPlayers[id][entityId] then EntityPlayers[id][entityId] = {} end
    for i=1, #EntityPlayers[id][entityId] do
        local player = EntityPlayers[id][entityId][i]
        if player == source then
            table.remove(EntityPlayers[id][entityId], i)
            break
        end
    end
    table.insert(EntityPlayers[id][entityId], source)
end)

RegisterNetEvent("pickle_clubs:unrenderEntity", function(id, entityId, ...)
    local source = source
    local club = Clubs[id]
    if not club then return end
    local entity = club.entities[entityId]
    if not entity then return end
    if not RegisteredEntityTypes[entity.type] then return end
    RegisteredEntityTypes[entity.type].onUnrender(id, entityId, source, ...)
    if not EntityPlayers[id] then EntityPlayers[id] = {} end
    if not EntityPlayers[id][entityId] then EntityPlayers[id][entityId] = {} end
    for i=1, #EntityPlayers[id][entityId] do
        local player = EntityPlayers[id][entityId][i]
        if player == source then
            table.remove(EntityPlayers[id][entityId], i)
            break
        end
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    for k,v in pairs(EntityPlayers) do
        for entityId, players in pairs(v) do
            for i=1, #players do
                local player = players[i]
                if player == src then
                    table.remove(players, i)
                    break
                end
            end
        end
    end
end)

RegisterNetEvent("pickle_moneywash:initializePlayer", function()
    local src = source
    local moneyCounters = {}
    if PMW_Entities and PMW_Entities.GetByType then
        moneyCounters = PMW_Entities.GetByType("moneycounter")
    end
    TriggerClientEvent("pickle_moneywash:initializePlayer", src, {
        moneyCounters = moneyCounters,
        moneyProcessors = MoneyProcessors,
    })
    if PMW_Entities and PMW_Entities.SyncPlayer then
        PMW_Entities.SyncPlayer(src)
    end
end)

CreateThread(function()
    -- Simulated Club pre-database setup
    RegisterClub({
        id = 67,
        label = "Vanilla Unicorn",
        description = "The Vanilla Unicorn is a club that serves alcohol and music.",
        coords = vector3(119.1173, -1289.0688, 28.2532),
        entities = {
            ["abc-123456"] = {
                type = "club_entry",
                bouncer = {
                    ped = "bouncer_1",
                    coords = vector3(127.9870, -1299.3616, 28.2327), 
                    heading = 210.3588
                },
                line = {
                    direction = "forward",
                    coords = vector3(129.5437, -1299.7993, 28.2327),
                    heading = 29.7786
                }
            },
            ["abc-123457"] = {
                type = "bouncer",
                bouncer = {
                    ped = "bouncer_1",
                    coords = vector3(113.8438, -1302.6359, 28.0192),
                    heading = 293.9726
                }
            }
        }
    }, true)
end)