ConfigSV = {}

-- Discord Logging Configuration
ConfigSV.DiscordLogs = {
    enabled = true,
    webhook = "", -- Discord webhook URL - Add your webhook URL here
    botName = "Money Wash System",
    botAvatar = "", -- Optional bot avatar URL
}

-- Log type colors
local LogColors = {
    money_counter_counted = 3447003,      -- Blue
    processor_deposit = 3066993,          -- Green
    processor_withdraw = 15844367,         -- Gold
    processor_unlock = 10181046,           -- Purple
    processor_complete = 15105570,         -- Orange
    entity_created = 3066993,              -- Green
    entity_deleted = 15158332,              -- Red
    entity_updated = 16776960,              -- Yellow
}

-- Get player information for logging
local function GetPlayerInfo(source)
    if not source or source == 0 then
        return {
            name = "Unknown",
            identifier = "unknown",
            serverId = 0,
            steam = "N/A",
            discord = "N/A",
        }
    end

    local name = "Unknown"
    local identifier = "unknown"
    
    -- Try to get character name
    if type(GetPlayerCharacterName) == "function" then
        name = GetPlayerCharacterName(source) or GetPlayerName(source) or "Unknown"
    else
        name = GetPlayerName(source) or "Unknown"
    end
    
    -- Try to get identifier
    if type(GetIdentifier) == "function" then
        identifier = GetIdentifier(source) or "unknown"
    end
    
    -- Get additional identifiers
    local identifiers = GetPlayerIdentifiers(source) or {}
    local steam = "N/A"
    local discord = "N/A"
    
    for _, id in ipairs(identifiers) do
        if string.find(id, "steam:") then
            steam = id
        elseif string.find(id, "discord:") then
            discord = id
        end
    end
    
    return {
        name = name,
        identifier = identifier,
        serverId = source,
        steam = steam,
        discord = discord,
    }
end

-- Format coordinates for display
local function FormatCoords(coords)
    if not coords then return "N/A" end
    if type(coords) == "table" then
        return string.format("%.2f, %.2f, %.2f", coords.x or 0, coords.y or 0, coords.z or 0)
    end
    return tostring(coords)
end

-- Main Discord logging function
function ConfigSV.LogToDiscord(logType, source, data)
    -- Check if logging is enabled
    if not ConfigSV.DiscordLogs or not ConfigSV.DiscordLogs.enabled then
        return
    end
    
    -- Check if webhook is configured
    local webhook = ConfigSV.DiscordLogs.webhook
    if not webhook or webhook == "" then
        return
    end
    
    -- Get log color
    local color = LogColors[logType] or 9807270 -- Default gray
    
    -- Get player info
    local playerInfo = GetPlayerInfo(source)
    
    -- Build embed fields
    local fields = {}
    
    -- Add player information
    table.insert(fields, {
        name = "Player",
        value = playerInfo.name,
        inline = true
    })
    
    table.insert(fields, {
        name = "Server ID",
        value = tostring(playerInfo.serverId),
        inline = true
    })
    
    table.insert(fields, {
        name = "Identifier",
        value = playerInfo.identifier,
        inline = true
    })
    
    -- Add custom data fields
    if data then
        if data.amount then
            local amountStr = GetCurrencyString and GetCurrencyString(data.amount) or ("$" .. tostring(data.amount))
            table.insert(fields, {
                name = "Amount",
                value = amountStr,
                inline = true
            })
        end
        
        if data.counterId then
            table.insert(fields, {
                name = "Counter ID",
                value = tostring(data.counterId),
                inline = true
            })
        end
        
        if data.processorId then
            table.insert(fields, {
                name = "Processor ID",
                value = tostring(data.processorId),
                inline = true
            })
        end
        
        if data.entityId then
            table.insert(fields, {
                name = "Entity ID",
                value = tostring(data.entityId),
                inline = true
            })
        end
        
        if data.entityType then
            table.insert(fields, {
                name = "Entity Type",
                value = tostring(data.entityType),
                inline = true
            })
        end
        
        if data.businessId then
            table.insert(fields, {
                name = "Business ID",
                value = tostring(data.businessId),
                inline = true
            })
        end
        
        if data.businessLabel then
            table.insert(fields, {
                name = "Business",
                value = tostring(data.businessLabel),
                inline = true
            })
        end
        
        if data.feePercent then
            table.insert(fields, {
                name = "Fee",
                value = string.format("%.1f%%", data.feePercent),
                inline = true
            })
        end
        
        if data.feeAmount then
            local feeStr = GetCurrencyString and GetCurrencyString(data.feeAmount) or ("$" .. tostring(data.feeAmount))
            table.insert(fields, {
                name = "Fee Amount",
                value = feeStr,
                inline = true
            })
        end
        
        if data.netAmount then
            local netStr = GetCurrencyString and GetCurrencyString(data.netAmount) or ("$" .. tostring(data.netAmount))
            table.insert(fields, {
                name = "Net Amount",
                value = netStr,
                inline = true
            })
        end
        
        if data.unlockCost then
            local costStr = GetCurrencyString and GetCurrencyString(data.unlockCost) or ("$" .. tostring(data.unlockCost))
            table.insert(fields, {
                name = "Unlock Cost",
                value = costStr,
                inline = true
            })
        end
        
        if data.coords then
            table.insert(fields, {
                name = "Location",
                value = FormatCoords(data.coords),
                inline = false
            })
        end
        
        if data.oldCoords then
            table.insert(fields, {
                name = "Old Location",
                value = FormatCoords(data.oldCoords),
                inline = false
            })
        end
        
        if data.newCoords then
            table.insert(fields, {
                name = "New Location",
                value = FormatCoords(data.newCoords),
                inline = false
            })
        end
        
        if data.duration then
            local hours = math.floor(data.duration / 3600)
            local minutes = math.floor((data.duration % 3600) / 60)
            local seconds = data.duration % 60
            local durationStr = string.format("%02d:%02d:%02d", hours, minutes, seconds)
            table.insert(fields, {
                name = "Duration",
                value = durationStr,
                inline = true
            })
        end
        
        if data.itemRefunded then
            table.insert(fields, {
                name = "Item Refunded",
                value = data.itemRefunded and "Yes" or "No",
                inline = true
            })
        end
        
        if data.placedViaItem then
            table.insert(fields, {
                name = "Placed Via",
                value = data.placedViaItem and "Item" or "Admin",
                inline = true
            })
        end
    end
    
    -- Add timestamp
    table.insert(fields, {
        name = "Timestamp",
        value = os.date("%Y-%m-%d %H:%M:%S"),
        inline = false
    })
    
    -- Build embed title based on log type
    local titles = {
        money_counter_counted = "💰 Money Counted",
        processor_deposit = "💵 Money Deposited",
        processor_withdraw = "💸 Money Withdrawn",
        processor_unlock = "🔓 Business Unlocked",
        processor_complete = "✅ Laundering Complete",
        entity_created = "➕ Entity Created",
        entity_deleted = "➖ Entity Deleted",
        entity_updated = "🔄 Entity Updated",
    }
    
    local title = titles[logType] or "📝 Money Wash Activity"
    
    -- Build embed
    local embed = {
        {
            title = title,
            color = color,
            fields = fields,
            footer = {
                text = ConfigSV.DiscordLogs.botName,
            },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }
    }
    
    -- Add avatar if configured
    local payload = {
        username = ConfigSV.DiscordLogs.botName,
        embeds = embed
    }
    
    if ConfigSV.DiscordLogs.botAvatar and ConfigSV.DiscordLogs.botAvatar ~= "" then
        payload.avatar_url = ConfigSV.DiscordLogs.botAvatar
    end
    
    -- Send webhook (async, non-blocking)
    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end
