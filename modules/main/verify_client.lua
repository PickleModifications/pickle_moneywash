RegisterNetEvent("pickle_moneywash:warnMissingItems", function(missing)
    if missing and #missing > 0 then
        print("^3[pickle_moneywash] WARNING: server reports missing items: " .. table.concat(missing, ", ") .. "^0")
    end
end)
