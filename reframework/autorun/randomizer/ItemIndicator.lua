-- Floating labels over world checks (same idea as RE4's item_indicator).
-- Scans on a timer only -- hooking SetItem.update / updateGimmick locked the game.
-- Does nothing when the toggle is off.

local ItemIndicator = {}

ItemIndicator.isInit = false
ItemIndicator.enabled = false
ItemIndicator.showItems = true
ItemIndicator.showBoxes = true
ItemIndicator.showContainers = true
ItemIndicator.showEnemies = true
ItemIndicator.showFiles = true
ItemIndicator.showHints = true
ItemIndicator.inLogicOnly = true
ItemIndicator.limitDistance = 40.0
-- Enemies move around, so refresh the list often and chase transforms every frame.
ItemIndicator.enemyScanInterval = 0.45
-- Everything else is slower; also rescans when you walk far enough.
ItemIndicator.staticScanInterval = 5.0
ItemIndicator.staticMoveRescan = 10.0
ItemIndicator.showCleared = false
-- Cap matches the Draw Distance slider max. We keep markers out this far and
-- filter against the live slider in Draw(), so dragging it doesn't need a rescan.
local max_draw_distance = 100.0

-- draw.world_text wants 0xAABBGGRR, not ARGB. Don't "fix" these.
ItemIndicator.colorItem = 0xFFFFFFFF -- white
ItemIndicator.colorKey = 0xFFEF99AF -- AP progression purple (#AF99EF)
ItemIndicator.colorBox = 0xFFFFFFFF -- white (same as normal items)
ItemIndicator.colorEnemy = 0xFF5555FF -- red (enemy kills)
ItemIndicator.colorFile = 0xFF55FF55 -- green (files)
ItemIndicator.colorHint = 0xFF00D7FF -- gold (hinted)
ItemIndicator.colorCleared = 0xFF888888 -- gray (already checked)

local markers = {}
local now = 0
local last_enemy_list_scan = 0
local last_static_scan = 0
local last_static_pos = nil
local last_logic_stamp = nil
local static_phase = 0
local static_burst_left = 0
local static_phases = { "containers", "items", "boxes", "files" }
local guid_cache = nil
local guid_cache_stamp = nil
local item_name_cache = {}
local item_by_name_cache = {}
-- GUIDs already covered by a locker/case label this cycle (skip the floor item).
local container_guids = {}
-- Container rows pulled out of Lookups once.
local container_locs = nil
local container_locs_stamp = nil
-- key -> { go, pos, failUntil }
local container_go_cache = {}
local folder_path_cache = {} -- folder_path -> folder, or false if missing
-- key -> { enemy, loc, label, kind }
local enemy_tracks = {}

local function can_run()
    if not ItemIndicator.enabled then
        return false
    end
    if not Scene or not Scene.isInGame or not Scene:isInGame() then
        return false
    end
    if Scene.isTransitioning and Scene.isTransitioning() then
        return false
    end
    return true
end

local function guid_string(guid)
    if not guid then
        return ""
    end
    if type(guid) == "string" then
        return string.lower(guid)
    end
    if Storage and Storage.GetGuidString then
        return string.lower(Storage.GetGuidString(guid) or "")
    end
    return ""
end

local function lookups_stamp()
    -- Cheap stamp so we rebuild the cache after Load / Reset Scripts.
    local locs = (Lookups and Lookups.locations) or {}
    return tostring(Lookups and Lookups.difficulty or "")
        .. "|"
        .. tostring(Archipelago and Archipelago.files_as_locations)
        .. "|"
        .. tostring(#locs)
end

-- Lookups.Load dumps assisted/hardcore/nightmare/inferno rows on top of standard
-- no matter what difficulty the slot is. Only show rows the client can match:
-- untagged ones, or ones tagged for the active difficulty (same rule as
-- _GetLocationFromLocationData).
local difficulty_flags = { "assisted", "hardcore", "nightmare", "inferno" }

local function row_for_difficulty(loc)
    if not loc then
        return true
    end
    local active = Lookups and Lookups.difficulty
    for _, flag in ipairs(difficulty_flags) do
        if loc[flag] then
            return flag == active
        end
    end
    return true
end

local function rebuild_guid_cache()
    guid_cache = {}
    for _, loc in pairs((Lookups and Lookups.locations) or {}) do
        local g = loc.object_guid
        if type(g) == "string" and g ~= "" and row_for_difficulty(loc) then
            guid_cache[string.lower(g)] = loc
        end
    end
    for _, loc in pairs((Lookups and Lookups.files) or {}) do
        local g = loc.object_guid
        if type(g) == "string" and g ~= "" then
            guid_cache[string.lower(g)] = loc
        end
    end
    guid_cache_stamp = lookups_stamp()
end

local function location_by_guid(guid)
    local key = guid_string(guid)
    if key == "" then
        return nil
    end
    if guid_cache == nil or guid_cache_stamp ~= lookups_stamp() then
        rebuild_guid_cache()
    end
    return guid_cache[key]
end

local function is_cleared(loc, guid)
    -- loc.sent from AP is what we care about for multiworld state.
    if loc and loc.sent then
        return true
    end
    -- Don't use Storage.checkedItemGuids. That table is per AP seed/slot, not per
    -- in-game save -- a new save on the same seed still has old GUIDs and would
    -- hide live Enable=true pickups.
    return false
end

local function extract_id(value)
    if value == nil then
        return nil
    end
    if type(value) == "number" then
        return value
    end
    local n = tonumber(value)
    if n ~= nil then
        return n
    end
    local s = tostring(value)
    local inner = string.match(s, "%((%-?%d+)%)")
    if inner then
        return tonumber(inner)
    end
    return tonumber(s)
end

local function item_display_name(item_id, weapon_id)
    item_id = tonumber(item_id) or -1
    weapon_id = tonumber(weapon_id) or -1
    local cache_key = (weapon_id > 0 and ("w" .. weapon_id)) or ("i" .. item_id)
    local cached = item_name_cache[cache_key]
    if cached then
        return cached.name, cached.info
    end

    local looking_weapon = weapon_id > 0
    local target = looking_weapon and weapon_id or item_id
    local name, info = nil, nil

    for _, item in pairs((Lookups and Lookups.items) or {}) do
        local decimal = tonumber(item.decimal)
        if decimal ~= nil and decimal == target then
            local is_weapon = item.type == "Weapon" or item.type == "Subweapon"
            if is_weapon == looking_weapon then
                name = item.name
                info = item
                break
            end
        end
    end

    if not name then
        if weapon_id > 0 then
            name = "Weapon " .. tostring(weapon_id)
        elseif item_id > 0 then
            name = "Item " .. tostring(item_id)
        else
            name = "Item"
        end
    end

    item_name_cache[cache_key] = { name = name, info = info }
    return name, info
end

-- Lockers / cases have no live SetItem until you open them, so their vanilla
-- contents only exist as a name on the location row.
local function item_info_by_name(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local cached = item_by_name_cache[name]
    if cached then
        return cached.info
    end

    local info = nil
    for _, item in pairs((Lookups and Lookups.items) or {}) do
        if item.name == name then
            info = item
            break
        end
    end

    item_by_name_cache[name] = { info = info }
    return info
end

local function is_progression_item(info)
    if not info then
        return false
    end
    return info.progression == 1 or info.type == "Key" or info.type == "Gating"
end

-- Most rows have no randomized field at all, which means AP shuffled the spot.
-- Only an explicit 0 leaves the vanilla item sitting there. No loc means it
-- isn't a check, so the world item is real.
local function keeps_vanilla_item(loc)
    if loc == nil then
        return true
    end
    return tonumber(loc.randomized) == 0
end

local function location_label(loc, fallback)
    if loc and loc.name and loc.name ~= "" then
        return loc.name
    end
    return fallback or "Item"
end

local function color_for_kind(kind)
    if kind == "hint" then
        return ItemIndicator.colorHint
    end
    if kind == "key" then
        return ItemIndicator.colorKey
    end
    if kind == "box" then
        return ItemIndicator.colorBox
    end
    if kind == "enemy" then
        return ItemIndicator.colorEnemy
    end
    if kind == "file" then
        return ItemIndicator.colorFile
    end
    return ItemIndicator.colorItem
end

local function is_hinted_location(loc)
    if not ItemIndicator.showHints or not loc then
        return false
    end
    if not Archipelago or not Archipelago.IsLocationHinted then
        return false
    end
    local ok, hinted = pcall(Archipelago.IsLocationHinted, loc)
    return ok and hinted == true
end

local function is_in_logic(loc)
    if not ItemIndicator.inLogicOnly then
        return true
    end
    -- Offline = no collected list, so just show everything.
    if not Archipelago or not Archipelago.IsConnected or not Archipelago.IsConnected() then
        return true
    end
    if not loc then
        return false
    end
    if not Logic or not Logic.IsLocationInLogic then
        return true
    end
    local ok, in_logic = pcall(Logic.IsLocationInLogic, loc)
    return ok and in_logic == true
end

local function player_position()
    local ok, pos = pcall(function()
        return Player.GetCurrentPosition()
    end)
    if ok then
        return pos
    end
    return nil
end

-- cleared_hint: caller already knows this one is looted (SetItem disabled, box
-- broken). Only matters for styling while Show Cleared Labels is on.
local function set_marker(key, pos, text, kind, ppos, loc, cleared_hint)
    if not pos or not ppos or not text then
        return
    end
    local distance = nil
    local ok = pcall(function()
        distance = (ppos - pos):length()
    end)
    if not ok or distance == nil then
        return
    end
    if distance > max_draw_distance then
        return
    end

    -- In-logic / distance / hint styling get decided in Draw() so flipping those
    -- toggles shows up immediately without waiting for a rescan.
    markers[key] = {
        pos = pos,
        label = text,
        color = color_for_kind(kind),
        update_time = now,
        kind = kind,
        loc = loc,
        guid = loc and guid_string(loc.object_guid) or "",
        cleared = cleared_hint == true,
    }
end

local function each_component(type_name, fn)
    local scene = Scene.getSceneObject and Scene.getSceneObject()
    if not scene then
        return
    end

    local comps = nil
    pcall(function()
        comps = scene:call(
            "findComponents(System.Type)",
            sdk.typeof(sdk.game_namespace(type_name))
        )
    end)
    if not comps then
        return
    end

    if comps.get_elements then
        local elements = nil
        pcall(function()
            elements = comps:get_elements()
        end)
        if elements then
            for _, comp in pairs(elements) do
                if comp ~= nil then
                    pcall(fn, comp)
                end
            end
            return
        end
    end

    local size = nil
    pcall(function()
        size = comps:get_size()
    end)
    if size == nil then
        pcall(function()
            size = comps:call("get_size")
        end)
    end
    size = tonumber(size)
    if not size or size < 1 then
        return
    end
    -- Cap this so a huge scene can't freeze a frame.
    if size > 256 then
        size = 256
    end

    for i = 0, size - 1 do
        local comp = nil
        pcall(function()
            comp = comps[i]
        end)
        if comp == nil then
            pcall(function()
                comp = comps:call("get_Item", i)
            end)
        end
        if comp ~= nil then
            pcall(fn, comp)
        end
    end
end

local function enemies_slot_on()
    if not Archipelago or not Archipelago.enemy_kills then
        return false
    end
    local mode = tostring(Archipelago.enemy_kills)
    return mode ~= "None" and mode ~= "Off" and mode ~= "false"
end

local function files_slot_on()
    return Archipelago and Archipelago.files_as_locations == true
end

local function scan_items(ppos)
    if not ItemIndicator.showItems then
        return
    end

    each_component("gimmick.action.SetItem", function(set_item)
        local addr = set_item:get_address()
        if not addr then
            return
        end
        local key = "i:" .. tostring(addr)

        local save = set_item:call("get_SaveData")
        if not save then
            return
        end

        -- Trust live Enable only. Storage GUID checks stick across new saves on
        -- the same seed and were falsely hiding nearby pickups.
        local enabled = save:get_field("Enable") == true
        if not enabled and not ItemIndicator.showCleared then
            return
        end

        local guid = save:get_field("ItemPositionGuid")
        local gkey = guid_string(guid)
        if gkey ~= "" and container_guids[gkey] then
            return
        end

        local loc = location_by_guid(guid)

        local pos = set_item:call("get_Position")
        if pos == nil then
            pos = save:get_field("Position")
        end
        if pos == nil then
            return
        end

        local item_id = extract_id(save:get_field("Type")) or -1
        local weapon_id = extract_id(save:get_field("WeaponType")) or -1
        local item_name, item_info = item_display_name(item_id, weapon_id)
        local kind = "item"
        -- The world object still holds the vanilla item, so its type is only
        -- honest where AP left the spot alone. Everywhere else it's whatever
        -- got shuffled in, so don't promise progression with purple.
        if keeps_vanilla_item(loc) and is_progression_item(item_info) then
            kind = "key"
        end

        set_marker(key, pos, location_label(loc, item_name), kind, ppos, loc, not enabled)
    end)
end

-- Lockers / attache cases -- Lookups only. The item usually isn't a live SetItem
-- until you open it, but the parent GO (sm70_101_InCase etc.) is already there.
local function is_container_object_name(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    local lower = string.lower(name)
    return string.find(lower, "locker", 1, true) ~= nil
        or string.find(lower, "incase", 1, true) ~= nil
        or string.find(lower, "_acase", 1, true) ~= nil
        or string.find(lower, "attache", 1, true) ~= nil
        or string.find(lower, "keylock", 1, true) ~= nil
        or string.find(lower, "chestpos", 1, true) ~= nil
        or string.find(lower, "inlocker", 1, true) ~= nil
end

local function is_container_location(loc)
    if not loc then
        return false
    end
    if is_container_object_name(loc.parent_object) or is_container_object_name(loc.item_object) then
        return true
    end
    local n = string.lower(loc.name or "")
    if n == "" then
        return false
    end
    -- Skip non-containers that just happen to say "case"/"locker" in the name.
    if string.find(n, "nemesis", 1, true)
        or string.find(n, "supply case", 1, true)
        or string.find(n, "display", 1, true)
        or string.find(n, "emergency", 1, true)
        or string.find(n, "floor by", 1, true)
        or string.find(n, "by locker", 1, true)
        or string.find(n, "near locker", 1, true)
        or string.find(n, "breakable", 1, true)
    then
        return false
    end
    if n == "attache case" or string.find(n, "attache case", 1, true) then
        return true
    end
    if n == "id case" then
        return true
    end
    if string.find(n, "locker", 1, true) then
        return true
    end
    if string.match(n, "^case on ") or string.match(n, "^case near ") then
        return true
    end
    return false
end

local function game_object_world_pos(go)
    local pos = nil
    pcall(function()
        local t = go and go:call("get_Transform")
        pos = t and t:call("get_Position")
    end)
    return pos
end

local function game_object_folder_path(go)
    local path = nil
    pcall(function()
        local folder = go and go:call("get_Folder")
        path = folder and folder:call("get_Path")
    end)
    return path
end

local function find_folder_by_path(scene, folder_path)
    if not scene or type(folder_path) ~= "string" or folder_path == "" then
        return nil
    end
    local cached = folder_path_cache[folder_path]
    if cached ~= nil then
        if cached.failUntil and now < cached.failUntil then
            return cached.folder
        end
        if cached.folder then
            local alive = false
            pcall(function()
                alive = cached.folder:call("get_Path") ~= nil
            end)
            if alive then
                return cached.folder
            end
        end
        folder_path_cache[folder_path] = nil
    end

    local folder = nil
    local short_name = string.match(folder_path, "([^/]+)$")
    if short_name then
        pcall(function()
            folder = scene:call("findFolder(System.String)", short_name)
        end)
    end
    if not folder then
        folder_path_cache[folder_path] = { folder = nil, failUntil = now + 3.0 }
        return nil
    end
    local path = nil
    pcall(function()
        path = folder:call("get_Path")
    end)
    -- Only trust folder when the full path matches (duplicate leaf names exist).
    if path == folder_path then
        folder_path_cache[folder_path] = { folder = folder, failUntil = nil }
        return folder
    end
    folder_path_cache[folder_path] = { folder = nil, failUntil = now + 3.0 }
    return nil
end

local function find_container_game_object(loc)
    local scene = Scene.getSceneObject and Scene.getSceneObject()
    if not scene or not loc then
        return nil
    end

    -- Prefer the parent container GO. Only fall back to item_object when the
    -- parent itself looks like a container (avoids labeling random sm70_* pickups).
    local names = {}
    if type(loc.parent_object) == "string" and loc.parent_object ~= "" then
        table.insert(names, loc.parent_object)
    end
    if is_container_object_name(loc.parent_object)
        and type(loc.item_object) == "string"
        and loc.item_object ~= ""
        and loc.item_object ~= loc.parent_object
    then
        table.insert(names, loc.item_object)
    end
    if #names < 1 then
        return nil
    end

    local folder = find_folder_by_path(scene, loc.folder_path)
    for _, name in ipairs(names) do
        local go = nil
        if folder then
            pcall(function()
                go = scene:call(
                    "findGameObject(System.String, via.Folder)",
                    name,
                    folder
                )
            end)
        end
        if not go then
            pcall(function()
                go = scene:call("findGameObject(System.String)", name)
            end)
            if go and type(loc.folder_path) == "string" and loc.folder_path ~= "" then
                local path = game_object_folder_path(go)
                if path and path ~= loc.folder_path then
                    go = nil
                end
            end
        end
        if go then
            return go
        end
    end
    return nil
end

local function get_container_locations()
    local stamp = (Archipelago and Archipelago.collectedStamp) or 0
    -- Rebuild when Lookups reloads or the logic inventory changes.
    local lookups_count = Lookups and Lookups.locations and #Lookups.locations or 0
    local want_stamp = tostring(stamp) .. ":" .. tostring(lookups_count)
    if container_locs and container_locs_stamp == want_stamp then
        return container_locs
    end

    -- Lookups holds every difficulty's rows at once, so one physical container
    -- can show up twice. Subway Office "Right Locker" is the real row plus a
    -- nightmare/inferno row with no object_guid but the same parent_object and
    -- folder_path. Both resolve to the same locker, and the guid-less one can
    -- never go loc.sent, so its label sticks after you loot. Keep one row per
    -- container, preferring the one we can actually clear.
    local list = {}
    local seen = {}
    for _, loc in pairs((Lookups and Lookups.locations) or {}) do
        if is_container_location(loc) and row_for_difficulty(loc) then
            local dedupe_key = string.lower(table.concat({
                tostring(loc.region or ""),
                tostring(loc.name or ""),
                tostring(loc.parent_object or ""),
                tostring(loc.folder_path or ""),
            }, "|"))
            local at = seen[dedupe_key]
            if at == nil then
                table.insert(list, loc)
                seen[dedupe_key] = #list
            elseif guid_string(loc.object_guid) ~= ""
                and guid_string(list[at].object_guid) == ""
            then
                list[at] = loc
            end
        end
    end
    container_locs = list
    container_locs_stamp = want_stamp
    return list
end

local function resolve_container(loc, key)
    local cached = container_go_cache[key]
    if cached and cached.go then
        local pos = game_object_world_pos(cached.go)
        if pos then
            cached.pos = pos
            return cached.go, pos
        end
        cached.go = nil
    end

    -- Don't keep searching scenes that aren't loaded.
    if cached and cached.failUntil and now < cached.failUntil then
        return nil, cached.pos
    end

    local go = find_container_game_object(loc)
    if not go then
        container_go_cache[key] = {
            go = nil,
            pos = cached and cached.pos or nil,
            failUntil = now + 4.0,
        }
        return nil, cached and cached.pos or nil
    end

    local pos = game_object_world_pos(go)
    container_go_cache[key] = {
        go = go,
        pos = pos,
        failUntil = nil,
    }
    return go, pos
end

local function scan_containers(ppos)
    if not ItemIndicator.showContainers then
        return
    end

    -- Refresh claimed GUIDs for this cycle.
    container_guids = {}

    for _, loc in ipairs(get_container_locations()) do
        if is_cleared(loc, loc.object_guid) and not ItemIndicator.showCleared then
            goto next_container
        end
        local gkey = guid_string(loc.object_guid)
        if gkey ~= "" then
            container_guids[gkey] = true
        end

        local key = (gkey ~= "" and ("c:" .. gkey))
            or ("c:" .. tostring(loc.region or "") .. "|" .. tostring(loc.name or ""))

        local go, pos = resolve_container(loc, key)
        if not go or not pos then
            goto next_container
        end

        -- Same rule as loose items, just sourced from original_item since
        -- there's nothing live to read inside a shut locker.
        local kind = "item"
        if keeps_vanilla_item(loc)
            and is_progression_item(item_info_by_name(loc.original_item))
        then
            kind = "key"
        end

        set_marker(
            key,
            pos,
            location_label(loc, loc.name or "Container"),
            kind,
            ppos,
            loc,
            is_cleared(loc, loc.object_guid)
        )
        ::next_container::
    end
end

local function scan_boxes(ppos)
    if not ItemIndicator.showBoxes then
        return
    end

    each_component("escape.gimmick.action.EsGimmickRandomContainer", function(comp)
        local addr = comp:get_address()
        if not addr then
            return
        end
        local key = "b:" .. tostring(addr)

        local hidden = false
        pcall(function()
            hidden = comp:call("get_IsHide") == true
        end)
        if hidden and not ItemIndicator.showCleared then
            return
        end

        local item_guid = ""
        pcall(function()
            local item_positions = comp:call("get_generatedItemPositions")
            if item_positions then
                item_guid = guid_string(item_positions:get_field("MyGuid"))
            end
        end)

        local loc = item_guid ~= "" and location_by_guid(item_guid) or nil
        if is_cleared(loc, item_guid) and not ItemIndicator.showCleared then
            return
        end

        local pos = nil
        pcall(function()
            local go = comp:call("get_GameObject")
            local t = go and go:call("get_Transform")
            pos = t and t:call("get_Position")
        end)
        if pos then
            set_marker(key, pos, location_label(loc, "Breakable Box"), "box", ppos, loc, hidden)
        end
    end)
end

local function enemy_world_pos(enemy)
    local pos = nil
    pcall(function()
        local go = enemy and enemy:call("get_GameObject")
        local t = go and go:call("get_Transform")
        pos = t and t:call("get_Position")
    end)
    return pos
end

-- Rebuild which AP enemies to track. Positions get chased separately.
local function scan_enemy_list()
    enemy_tracks = {}
    if not ItemIndicator.showEnemies or not enemies_slot_on() then
        return
    end
    if not EnemyInvisible or not EnemyInvisible.GetActiveEnemies then
        return
    end

    local list = EnemyInvisible.GetActiveEnemies()
    for _, enemy in ipairs(list) do
        local guid = ""
        local addr = nil
        pcall(function()
            guid = guid_string(enemy:call("get_ContextGUID"))
            addr = enemy:get_address()
        end)
        local key = "e:" .. (guid ~= "" and guid or tostring(addr or "?"))
        local loc = location_by_guid(guid)
        if not loc then
            goto continue
        end
        if is_cleared(loc, guid) and not ItemIndicator.showCleared then
            goto continue
        end
        enemy_tracks[key] = {
            enemy = enemy,
            loc = loc,
            label = location_label(loc, "Enemy"),
            kind = "enemy",
        }
        ::continue::
    end
end

-- Just chase the tracked enemy transforms -- cheap.
local function update_enemy_markers(ppos)
    if not ppos then
        return
    end
    if not ItemIndicator.showEnemies or not enemies_slot_on() then
        for key, _ in pairs(markers) do
            if type(key) == "string" and string.sub(key, 1, 2) == "e:" then
                markers[key] = nil
            end
        end
        enemy_tracks = {}
        return
    end

    for key, track in pairs(enemy_tracks) do
        local pos = enemy_world_pos(track.enemy)
        if not pos then
            enemy_tracks[key] = nil
            markers[key] = nil
        else
            set_marker(key, pos, track.label, track.kind, ppos, track.loc)
        end
    end

    -- Drop markers for enemies we aren't tracking anymore.
    for key, _ in pairs(markers) do
        if type(key) == "string" and string.sub(key, 1, 2) == "e:" and not enemy_tracks[key] then
            markers[key] = nil
        end
    end
end

local function vec_distance(a, b)
    local d = nil
    pcall(function()
        d = (a - b):length()
    end)
    return d
end

local function collider_center(game_object)
    if not game_object then
        return nil
    end
    local center = nil
    pcall(function()
        local colliders = game_object:call(
            "getComponent(System.Type)",
            sdk.typeof("via.physics.Colliders")
        )
        if not colliders then
            return
        end
        local aabb = colliders:call("get_BoundingAabb")
        if aabb == nil then
            aabb = colliders:call("calculateBoundingAabb")
        end
        if aabb ~= nil then
            center = aabb:call("getCenter")
        end
    end)
    return center
end

local function transform_pos(game_object)
    local pos = nil
    pcall(function()
        local t = game_object and game_object:call("get_Transform")
        pos = t and t:call("get_Position")
    end)
    return pos
end

-- Figure out where the actual file prop is. EsFileGetSettings often lives on a
-- control object nowhere near the paper mesh -- prefer the named File0XX object
-- and its collider center (same volume the white interact prompt uses).
local function resolve_file_world_pos(loc, file_id, settings_go)
    -- The transform is where the prop actually sits. Collider center is the
    -- nicer anchor (it's the volume the interact prompt uses) but some file
    -- objects hand back a junk AABB that lands across the map, so only take it
    -- when it agrees with the transform.
    local function pos_of(go)
        if not go then
            return nil
        end

        local base = transform_pos(go)
        if base == nil then
            return collider_center(go)
        end

        local center = collider_center(go)
        if center ~= nil then
            local off = vec_distance(base, center)
            if off ~= nil and off <= 5.0 then
                return center
            end
        end

        return base
    end

    if loc and Files and Files.FindWorldObject then
        local object_name = loc.item_object
        if (not object_name or object_name == "") and loc.file_id then
            object_name = loc.file_id
        end
        local named = nil
        pcall(function()
            named = Files.FindWorldObject(
                object_name,
                loc.folder_path,
                file_id,
                false
            )
        end)
        local pos = pos_of(named)
        if pos then
            return pos
        end
    end

    -- Same folder as the settings object -- catches File0XX when the JSON folder
    -- path find fails quietly.
    if settings_go and loc then
        local object_name = loc.item_object
        if object_name and object_name ~= "" then
            local named = nil
            pcall(function()
                local folder = settings_go:call("get_Folder")
                local scene = Scene.getSceneObject and Scene.getSceneObject()
                if scene and folder then
                    named = scene:call(
                        "findGameObject(System.String, via.Folder)",
                        object_name,
                        folder
                    )
                end
            end)
            local pos = pos_of(named)
            if pos then
                return pos
            end
        end
    end

    -- No settings-object fallback on purpose. That's the control object, so it
    -- plants a label wherever the manager sits -- usually right on top of you.
    return nil
end

local function location_by_file_id(file_id)
    file_id = tonumber(file_id)
    if not file_id then
        return nil
    end
    if Files and Files.GetLocation then
        return Files.GetLocation(file_id)
    end
    local needle = string.format("Mes_File_%02d", file_id)
    for _, loc in pairs((Lookups and Lookups.files) or {}) do
        if loc.file_id == needle then
            return loc
        end
    end
    return nil
end

local function each_file_id_on_settings(comp, fn)
    local setting_list = nil
    pcall(function()
        setting_list = comp:get_field("SettingList")
    end)
    if not setting_list then
        return
    end

    local function handle_param(param)
        if not param then
            return
        end
        local file_id_list = nil
        pcall(function()
            file_id_list = param:get_field("FileIdList")
        end)
        if not file_id_list then
            return
        end
        local count = 0
        pcall(function()
            count = file_id_list:call("get_Count") or 0
        end)
        for i = 0, count - 1 do
            local raw = nil
            pcall(function()
                raw = file_id_list:call("get_Item", i)
            end)
            local id = extract_id(raw)
            if id then
                fn(id)
            end
        end
    end

    -- Param[] native array
    local length = nil
    pcall(function()
        length = setting_list:get_size()
    end)
    if length == nil then
        pcall(function()
            length = setting_list.Length or setting_list.length
        end)
    end
    length = tonumber(length)
    if length and length > 0 then
        for i = 0, math.min(length, 16) - 1 do
            local param = nil
            pcall(function()
                param = setting_list[i]
            end)
            if param == nil then
                pcall(function()
                    param = setting_list:call("GetValue", i)
                end)
            end
            handle_param(param)
        end
        return
    end

    -- Fallback: List-like
    local count = nil
    pcall(function()
        count = setting_list:call("get_Count")
    end)
    count = tonumber(count)
    if count and count > 0 then
        for i = 0, math.min(count, 16) - 1 do
            local param = nil
            pcall(function()
                param = setting_list:call("get_Item", i)
            end)
            handle_param(param)
        end
    end
end

local function scan_files(ppos)
    if not ItemIndicator.showFiles or not files_slot_on() then
        return
    end

    local labeled = {}

    -- Live EsFileGetSettings tells us which file IDs are loaded; position comes
    -- from the named File0XX prop / collider (not the settings control object).
    each_component("gimmick.option.EsFileGetSettings", function(comp)
        local settings_go = nil
        pcall(function()
            settings_go = comp:call("get_GameObject")
        end)

        each_file_id_on_settings(comp, function(file_id)
            local loc = location_by_file_id(file_id)
            if not loc then
                return
            end
            if is_cleared(loc, nil) and not ItemIndicator.showCleared then
                return
            end
            local key = "f:" .. tostring(loc.file_id or file_id)
            if labeled[key] then
                return
            end

            local pos = resolve_file_world_pos(loc, file_id, settings_go)
            if not pos then
                return
            end
            labeled[key] = true
            set_marker(
                key,
                pos,
                location_label(loc, loc.name or ("File " .. tostring(file_id))),
                "file",
                ppos,
                loc
            )
        end)
    end)

    -- Fallback for any AP file not attached to a live EsFileGetSettings.
    if not Files or not Files.FindWorldObject then
        return
    end

    for _, loc in pairs((Lookups and Lookups.files) or {}) do
        local key = "f:" .. tostring(loc.file_id or loc.item_object or "?")
        if labeled[key] then
            goto continue
        end
        if is_cleared(loc, nil) and not ItemIndicator.showCleared then
            goto continue
        end

        local object_name = loc.item_object
        if (not object_name or object_name == "") and loc.file_id then
            object_name = loc.file_id
        end
        if not object_name or object_name == "" then
            goto continue
        end

        local file_id = tonumber(string.match(tostring(loc.file_id or ""), "(%d+)$"))
        local pos = resolve_file_world_pos(loc, file_id, nil)
        if pos then
            labeled[key] = true
            set_marker(key, pos, location_label(loc, object_name), "file", ppos, loc)
        end
        ::continue::
    end
end

local function clear_markers_for_phase(phase)
    local prefix = nil
    if phase == "containers" then
        prefix = "c:"
    elseif phase == "items" then
        prefix = "i:"
    elseif phase == "boxes" then
        prefix = "b:"
    elseif phase == "files" then
        prefix = "f:"
    end
    if not prefix then
        return
    end
    for key, _ in pairs(markers) do
        if type(key) == "string" and string.sub(key, 1, #prefix) == prefix then
            markers[key] = nil
        end
    end
end

local function prune_stale_static_markers()
    local stale_after = ItemIndicator.staticScanInterval * (#static_phases + 1) + 1.0
    for key, entry in pairs(markers) do
        if type(key) == "string" and string.sub(key, 1, 2) ~= "e:" then
            if not entry or not entry.update_time or (now - entry.update_time) > stale_after then
                markers[key] = nil
            end
        end
    end
end

local function begin_static_burst()
    -- One heavy phase at a time so we don't hitch.
    static_burst_left = #static_phases
    static_phase = 0
end

local function static_scan_due(ppos)
    if static_burst_left > 0 then
        return true
    end

    local logic_stamp = (Archipelago and Archipelago.collectedStamp) or 0
    if last_logic_stamp ~= logic_stamp then
        last_logic_stamp = logic_stamp
        begin_static_burst()
        return true
    end
    if last_static_scan <= 0 then
        begin_static_burst()
        return true
    end
    if (now - last_static_scan) >= ItemIndicator.staticScanInterval then
        begin_static_burst()
        return true
    end
    if last_static_pos and ppos then
        local moved = vec_distance(ppos, last_static_pos)
        if moved and moved >= ItemIndicator.staticMoveRescan then
            begin_static_burst()
            return true
        end
    end
    return false
end

local function run_static_phase(ppos)
    static_phase = (static_phase % #static_phases) + 1
    local phase = static_phases[static_phase]
    clear_markers_for_phase(phase)

    if phase == "containers" then
        pcall(scan_containers, ppos)
    elseif phase == "items" then
        pcall(scan_items, ppos)
    elseif phase == "boxes" then
        pcall(scan_boxes, ppos)
    elseif phase == "files" then
        pcall(scan_files, ppos)
    end

    if static_burst_left > 0 then
        static_burst_left = static_burst_left - 1
    end
    if static_burst_left <= 0 then
        static_burst_left = 0
        last_static_scan = now
        last_static_pos = ppos
        prune_stale_static_markers()
    end
end

local function run_scan()
    if not can_run() then
        return
    end

    local ppos = player_position()
    if not ppos then
        return
    end

    -- Enemies: rebuild the watch list every so often, chase positions every frame.
    if ItemIndicator.showEnemies and enemies_slot_on() then
        if (now - last_enemy_list_scan) >= ItemIndicator.enemyScanInterval then
            last_enemy_list_scan = now
            pcall(scan_enemy_list)
        end
        pcall(update_enemy_markers, ppos)
    elseif next(enemy_tracks) ~= nil or next(markers) ~= nil then
        pcall(update_enemy_markers, ppos)
    end

    -- Everything else (items/boxes/lockers/files): slow timer, or after you walk far enough.
    if static_scan_due(ppos) then
        run_static_phase(ppos)
    end
end

-- Flip a category on/off in settings -> refresh that category right now instead
-- of waiting out the static scan interval.
local function refresh_phase_now(phase)
    now = os.clock()

    if phase == "enemies" then
        for key, _ in pairs(markers) do
            if type(key) == "string" and string.sub(key, 1, 2) == "e:" then
                markers[key] = nil
            end
        end
        enemy_tracks = {}
        last_enemy_list_scan = 0
        local ppos = player_position()
        if ppos and ItemIndicator.enabled then
            pcall(scan_enemy_list)
            pcall(update_enemy_markers, ppos)
        end
        return
    end

    clear_markers_for_phase(phase)
    if not ItemIndicator.enabled then
        return
    end

    local ppos = player_position()
    if not ppos then
        return
    end

    -- Each scan already bails early if its own toggle is off.
    if phase == "containers" then
        pcall(scan_containers, ppos)
    elseif phase == "items" then
        pcall(scan_items, ppos)
    elseif phase == "boxes" then
        pcall(scan_boxes, ppos)
    elseif phase == "files" then
        pcall(scan_files, ppos)
    end
end

local function refresh_all_now()
    refresh_phase_now("items")
    refresh_phase_now("boxes")
    refresh_phase_now("containers")
    refresh_phase_now("files")
    refresh_phase_now("enemies")
end

function ItemIndicator.Draw()
    if not ItemIndicator.enabled then
        return
    end

    now = os.clock()
    run_scan()

    local ppos = player_position()
    for _, entry in pairs(markers) do
        if entry and entry.label and entry.pos and is_in_logic(entry.loc) then
            local distance = nil
            if ppos then
                pcall(function()
                    distance = (ppos - entry.pos):length()
                end)
            end
            if distance == nil or distance <= ItemIndicator.limitDistance then
                local text = entry.label
                local color = entry.color or ItemIndicator.colorItem
                if is_hinted_location(entry.loc) then
                    text = "* " .. text
                    color = ItemIndicator.colorHint
                end
                -- Only shows up with Show Cleared Labels on; otherwise the scans
                -- never hand these to set_marker in the first place.
                if ItemIndicator.showCleared
                    and (entry.cleared or is_cleared(entry.loc, entry.guid))
                then
                    text = "[x] " .. text
                    color = ItemIndicator.colorCleared
                end
                if distance ~= nil then
                    text = string.format("%s: %.0f", text, distance)
                end
                pcall(function()
                    draw.world_text(text, entry.pos, color)
                end)
            end
        end
    end
end

function ItemIndicator.DrawSettings()
    local changed
    changed, ItemIndicator.enabled = imgui.checkbox("  Off / On Toggle", ItemIndicator.enabled)
    if changed and not ItemIndicator.enabled then
        markers = {}
        container_go_cache = {}
        folder_path_cache = {}
        container_guids = {}
        enemy_tracks = {}
        static_phase = 0
        static_burst_left = 0
        last_enemy_list_scan = 0
        last_static_scan = 0
        last_static_pos = nil
    end
    if changed and ItemIndicator.enabled then
        last_enemy_list_scan = 0
        last_static_scan = 0
        last_static_pos = nil
        static_phase = 0
        static_burst_left = 0
        refresh_all_now()
    end

    if ItemIndicator.enabled then
        changed, ItemIndicator.showItems = imgui.checkbox(
            "  Locations",
            ItemIndicator.showItems
        )
        if changed then
            refresh_phase_now("items")
        end

        changed, ItemIndicator.showBoxes = imgui.checkbox("  Breakable Boxes", ItemIndicator.showBoxes)
        if changed then
            refresh_phase_now("boxes")
        end

        changed, ItemIndicator.showContainers = imgui.checkbox(
            "  Lockers / Cases",
            ItemIndicator.showContainers
        )
        if changed then
            refresh_phase_now("containers")
        end

        if enemies_slot_on() then
            changed, ItemIndicator.showEnemies = imgui.checkbox(
                "  Enemies",
                ItemIndicator.showEnemies
            )
            if changed then
                refresh_phase_now("enemies")
            end
        else
            imgui.text_colored("  Enemy labels: (enemy kills off in slot)", 0xFF777777)
        end

        if files_slot_on() then
            changed, ItemIndicator.showFiles = imgui.checkbox(
                "  Files",
                ItemIndicator.showFiles
            )
            if changed then
                refresh_phase_now("files")
            end
        else
            imgui.text_colored("  File labels: (files off in slot)", 0xFF777777)
        end

        -- These three get applied in Draw(), so no rescan needed.
        changed, ItemIndicator.showHints = imgui.checkbox(
            "  Highlight Hinted Locations",
            ItemIndicator.showHints
        )

        changed, ItemIndicator.inLogicOnly = imgui.checkbox(
            "  Only Show In-Logic Checks",
            ItemIndicator.inLogicOnly
        )

        changed, ItemIndicator.limitDistance = imgui.slider_float(
            "Draw Distance",
            ItemIndicator.limitDistance,
            5.0,
            max_draw_distance,
            "%.0f"
        )
        changed, ItemIndicator.showCleared = imgui.checkbox(
            "  Show Cleared Labels",
            ItemIndicator.showCleared
        )
        if changed then
            refresh_all_now()
        end
    end
end

function ItemIndicator.Init()
    -- No hooks. Draw() bails early when the toggle is off.
    ItemIndicator.isInit = true
end

return ItemIndicator
