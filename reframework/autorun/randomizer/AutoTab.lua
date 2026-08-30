local AutoTab = {}

-- Push the current map zone to AP DataStorage so PopTracker can ActivateTab.
-- Key: "<slot>-re3r-currentMap"  Value: zone code (e.g. "downtown", "rpd_1f")

AutoTab.lastZone = nil
AutoTab.lastPush = 0
AutoTab.STORAGE_SUFFIX = "-re3r-currentMap"

-- zone code -> PopTracker tab titles (parent then child for nested tabs)
-- Kept here as documentation; the pack has the same mapping.
local function zone_from_map_name(map_name)
    if not map_name or map_name == "" or map_name == "Invalid" then
        return nil
    end

    -- "st03_0201_0 (134)" or bare "st03_0201_0"
    local name = tostring(map_name):match("^([%w_]+)") or tostring(map_name)
    local area, room = string.match(string.lower(name), "st(%d+)_(%d+)")
    area = tonumber(area)
    room = tonumber(room)
    if not area or not room then
        return nil
    end

    local block = math.floor(room / 100)

    -- RPD
    if area == 2 then
        if room >= 300 and room < 400 then
            -- courtyards / outside-ish
            return "rpd_outside"
        end
        if block <= 3 then
            return "rpd_1f"
        elseif block <= 5 then
            return "rpd_2f"
        end
        return "rpd_3f"
    end

    -- Downtown / Sewers / Clock / Demolition (all Location DownTown)
    if area == 3 then
        -- Sewers
        if room >= 600 and room < 700 then
            if room >= 614 and room <= 619 then
                return "sewers_upper"
            end
            return "sewers_lower"
        end
        -- Clock Tower
        if room >= 800 and room < 900 then
            if room == 806 then
                return "clock_plaza"
            end
            return "clock_tunnel"
        end
        -- Demolition storage
        if room >= 700 and room < 800 then
            return "demo_ground"
        end
        -- Substation / Power Maze / Demolition outdoor
        if room >= 400 and room < 500 then
            if room == 404 then
                return "substation"
            end
            -- 0402 Power Maze / Outdoor Area → Demolition ground floor
            return "demo_ground"
        end
        -- Subway Office
        if room >= 500 and room < 600 then
            return "subway_office"
        end
        -- st03_0201 (ticket gate / clock puzzle) and the early subway platforms
        -- are drawn on the Downtown tracker map, not Redstone Station.
        -- Redstone Station is a late-game overlay for a couple subway-access checks.
        return "downtown"
    end

    -- Hospital (+ underground storage)
    if area == 4 then
        if block <= 1 then
            return "hospital_1f"
        elseif block == 2 then
            return "hospital_2f"
        end
        return "hospital_storage"
    end

    -- NEST / Laboratory
    if area == 5 then
        if block <= 1 then
            return "nest_1f"
        elseif block == 2 then
            return "nest_2f"
        elseif block == 3 then
            return "nest_b1"
        end
        return "nest_b2"
    end

    return nil
end

local function get_scene_map_name()
    local map_name = nil
    pcall(function()
        local em = sdk.get_managed_singleton(sdk.game_namespace("EnemyManager"))
        if em then
            map_name = em:call("get_LastPlayerStaySceneID")
        end
    end)

    if map_name == nil then
        pcall(function()
            local mm = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.UIMapManager"))
            if mm then
                map_name = mm:call("get_SceneMapId")
            end
        end)
    end

    if map_name == nil then
        return nil
    end

    -- Enum ManagedObject -> "st03_0201_0 (134)" via tostring, or bare int
    local as_string = tostring(map_name)
    local named = as_string:match("^([%w_]+)%s*%(")
    if named then
        return named
    end

    -- bare numeric: resolve via typedef if possible
    local numeric = tonumber(as_string)
    if numeric ~= nil then
        local resolved = nil
        pcall(function()
            local typedef = sdk.find_type_definition(sdk.game_namespace("gamemastering.Map.ID"))
            if not typedef then
                return
            end
            for _, field in ipairs(typedef:get_fields()) do
                if field:is_static() then
                    local ok, val = pcall(function()
                        return field:get_data(nil)
                    end)
                    if ok and tonumber(val) == numeric then
                        resolved = field:get_name()
                        break
                    end
                end
            end
        end)
        return resolved
    end

    return as_string:match("^([%w_]+)") or as_string
end

local function push_zone(zone)
    if not Archipelago or not Archipelago.IsConnected or not Archipelago.IsConnected() then
        return false
    end
    if AP_REF == nil or AP_REF.APClient == nil then
        return false
    end

    local player_number = nil
    pcall(function()
        player_number = AP_REF.APClient:get_player_number()
    end)
    if player_number == nil or tonumber(player_number) < 0 then
        return false
    end

    local key = tostring(player_number) .. AutoTab.STORAGE_SUFFIX
    -- lua-apclientpp sample uses {{"replace", value}}; check boolean return.
    local ok, queued = pcall(function()
        return AP_REF.APClient:Set(key, zone, true, { { "replace", zone } })
    end)
    if not ok or not queued then
        ok, queued = pcall(function()
            return AP_REF.APClient:Set(key, zone, true, {
                { operation = "replace", value = zone }
            })
        end)
    end

    if ok and queued then
        log.info("[AutoTab] pushed " .. key .. " = " .. tostring(zone))
        return true
    end
    return false
end

function AutoTab.Init()
    if Scene and Scene.isTransitioning and Scene.isTransitioning() then
        return
    end

    -- don't spam Set calls
    if os.clock() - AutoTab.lastPush < 0.5 then
        return
    end

    local map_name = get_scene_map_name()
    local zone = zone_from_map_name(map_name)
    if zone == nil then
        return
    end

    if zone == AutoTab.lastZone then
        return
    end

    AutoTab.lastZone = zone
    AutoTab.lastPush = os.clock()
    push_zone(zone)
end

-- force a re-push after reconnect
function AutoTab.Reset()
    AutoTab.lastZone = nil
end

return AutoTab
