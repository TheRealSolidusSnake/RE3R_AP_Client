-- Client-side reachability (same rules as the apworld). Uses ReceivedItems, not inventory.

local Logic = {}

local reachable_cache = nil
local reachable_stamp = nil

function Logic.Invalidate()
    reachable_cache = nil
    reachable_stamp = nil
end

-- Same as apworld _has_items:
--   [] / nil           -> true
--   ["A", "B"]         -> AND (one requirement set)
--   [["A"], ["B"]]     -> OR of AND-sets
--   duplicates in a set require multiple copies
function Logic.HasItems(item_names, counts)
    counts = counts or (Archipelago and Archipelago.collectedItemCounts) or {}
    if item_names == nil then
        return true
    end
    if type(item_names) ~= "table" then
        return true
    end
    if #item_names < 1 then
        return true
    end

    local sets = item_names
    if type(item_names[1]) ~= "table" then
        sets = { item_names }
    end

    for _, req_set in ipairs(sets) do
        if type(req_set) == "table" then
            local need = {}
            for _, name in ipairs(req_set) do
                if type(name) == "string" and name ~= "" then
                    need[name] = (need[name] or 0) + 1
                end
            end

            local ok = true
            for name, count in pairs(need) do
                if (counts[name] or 0) < count then
                    ok = false
                    break
                end
            end
            if ok then
                return true
            end
        end
    end

    return false
end

local function condition_items(condition)
    if type(condition) ~= "table" then
        return nil
    end
    return condition.items
end

function Logic.GetReachableRegions()
    local stamp = (Archipelago and Archipelago.collectedStamp) or 0
    if reachable_cache ~= nil and reachable_stamp == stamp then
        return reachable_cache
    end

    local counts = (Archipelago and Archipelago.collectedItemCounts) or {}
    local connections = (Lookups and Lookups.regionConnections) or {}
    local reachable = { Menu = true }
    local queue = { "Menu" }
    local head = 1

    -- adjacency: from -> { { to = name, items = ... }, ... }
    local edges = {}
    for _, conn in pairs(connections) do
        if type(conn) == "table" and conn.from and conn.to then
            local limitation = conn.limitation
            if limitation ~= "ONE_SIDED_DOOR" then
                local from_name = conn.from
                local to_name = conn.to
                if not edges[from_name] then
                    edges[from_name] = {}
                end
                table.insert(edges[from_name], {
                    to = to_name,
                    items = condition_items(conn.condition),
                })
            end
        end
    end

    while head <= #queue do
        local region = queue[head]
        head = head + 1
        local outs = edges[region]
        if outs then
            for _, edge in ipairs(outs) do
                local dest = edge.to
                if dest and not reachable[dest] and Logic.HasItems(edge.items, counts) then
                    reachable[dest] = true
                    table.insert(queue, dest)
                end
            end
        end
    end

    reachable_cache = reachable
    reachable_stamp = stamp
    return reachable
end

function Logic.IsRegionInLogic(region_name)
    if type(region_name) ~= "string" or region_name == "" then
        return false
    end
    local reachable = Logic.GetReachableRegions()
    return reachable[region_name] == true
end

function Logic.IsLocationInLogic(loc)
    if not loc then
        return false
    end
    if not Logic.IsRegionInLogic(loc.region) then
        return false
    end
    return Logic.HasItems(condition_items(loc.condition))
end

return Logic
