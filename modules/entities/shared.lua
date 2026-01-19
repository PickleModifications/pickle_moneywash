-- Shared helpers for the generic placed-entity system.
-- Keep this file framework-agnostic and safe for both client/server.

PMW_EntityTypes = PMW_EntityTypes or {}

local Types = {}

local function normalizeType(entityType)
    if type(entityType) ~= "string" then return nil end
    entityType = string.lower(entityType)
    entityType = entityType:gsub("%s+", "")
    if entityType == "" then return nil end
    return entityType
end

PMW_EntityTypes.Register = function(entityType, def)
    local t = normalizeType(entityType)
    if not t then return false end
    def = def or {}
    Types[t] = {
        type = t,
        label = def.label or t,
        description = def.description,
    }
    return true
end

PMW_EntityTypes.Get = function(entityType)
    local t = normalizeType(entityType)
    if not t then return nil end
    return Types[t]
end

PMW_EntityTypes.All = function()
    local out = {}
    for t, def in pairs(Types) do
        out[#out + 1] = def
    end
    table.sort(out, function(a, b) return tostring(a.type) < tostring(b.type) end)
    return out
end

