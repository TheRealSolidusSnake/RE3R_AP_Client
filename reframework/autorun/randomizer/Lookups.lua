local Lookups = {}

Lookups.filepath = Manifest.mod_name .. "/"
Lookups.items = {}
Lookups.all_items = {}
Lookups.locations = {}
-- Separate source lists for GUID capture (not merged).
Lookups.itemLocations = {}
Lookups.enemyLocations = {}
Lookups.files = {}
Lookups.typewriters = {}
Lookups.regionConnections = {}
Lookups.difficulty = nil

function Lookups.Load(difficulty)
    local connections_file = Lookups.filepath .. "jill/a/region_connections.json"

    -- If this was already loaded and not cleared, don't load again
    if #Lookups.items > 0 and #Lookups.locations > 0 then
        if not Lookups.regionConnections or #Lookups.regionConnections < 1 then
            Lookups.regionConnections = json.load_file(connections_file) or {}
        end
        return
    end

    Lookups.difficulty = difficulty

    -- Hard-fixed for this client: Jill / Scenario A
    local jill_file = Lookups.filepath .. "/jill/items.json"
    local location_file = Lookups.filepath .. "jill/a/locations.json"
    local location_assisted_file = Lookups.filepath .. "jill/a/locations_assisted.json"
    local location_hardcore_file = Lookups.filepath .. "jill/a/locations_hardcore.json"
    local location_nightmare_file = Lookups.filepath .. "jill/a/locations_nightmare.json"
    local location_inferno_file = Lookups.filepath .. "jill/a/locations_inferno.json"
    local enemy_file = Lookups.filepath .. "jill/a/enemies.json"
    local files_file = Lookups.filepath .. "jill/a/files.json"
    local typewriter_file = Lookups.filepath .. "jill/a/typewriters.json"

    Lookups.scenario = "a" -- hard-fixed Jill Scenario A for this client
    Lookups.items = json.load_file(jill_file) or {}
    Lookups.locations = json.load_file(location_file) or {}
    Lookups.itemLocations = {}
    for _, loc in pairs(Lookups.locations) do
        table.insert(Lookups.itemLocations, loc)
    end
    Lookups.enemyLocations = {}
    Lookups.files = json.load_file(files_file) or {}
    Lookups.typewriters = json.load_file(typewriter_file) or {}
    Lookups.regionConnections = json.load_file(connections_file) or {}

    if Archipelago.files_as_locations then
        for _, fileLocation in pairs(Lookups.files) do
            table.insert(Lookups.locations, fileLocation)
        end
    end

    -- have to check for nightmare/hardcore/inferno files
    local inferno_locations = json.load_file(location_inferno_file) or {}
    local nightmare_locations = json.load_file(location_nightmare_file) or {}
    local hardcore_locations = json.load_file(location_hardcore_file) or {}
    local assisted_locations = json.load_file(location_assisted_file) or {}
    
    -- have to check for enemies now, too
    local enemy_name_suffix = ""

    if difficulty == "nightmare" or difficulty == "inferno" then
        enemy_file = Lookups.filepath .. "jill/a/enemies_extended.json"
        -- N/I enemies own their AP names. Data.py appends the same marker,
        -- so both sides build the identical location name.
        enemy_name_suffix = " (N/I)"
    end

    local enemy_locations = json.load_file(enemy_file) or {}

    if assisted_locations then
        for _, v in pairs(assisted_locations) do
            if not v['remove'] then -- ignore "remove" locations because they're for generation only
                v['assisted'] = true
                table.insert(Lookups.locations, v)
                table.insert(Lookups.itemLocations, v)
            end
        end
    end

    if inferno_locations then
        for _, v in pairs(inferno_locations) do
            if not v['remove'] then -- ignore "remove" locations because they're for generation only
                v['inferno'] = true
                table.insert(Lookups.locations, v)
                table.insert(Lookups.itemLocations, v)
            end
        end
    end

    if nightmare_locations then
        for _, v in pairs(nightmare_locations) do
            if not v['remove'] then -- ignore "remove" locations because they're for generation only
                v['nightmare'] = true
                table.insert(Lookups.locations, v)
                table.insert(Lookups.itemLocations, v)
            end
        end
    end

    if hardcore_locations then
        for _, v in pairs(hardcore_locations) do
            if not v['remove'] then -- ignore "remove" locations because they're for generation only
                v['hardcore'] = true
                table.insert(Lookups.locations, v)
                table.insert(Lookups.itemLocations, v)
            end
        end
    end

    if enemy_locations then
        for k, v in pairs(enemy_locations) do
            -- only add enemies that haven't been "excluded" because they can be missed
            if v['excluded'] == nil or v['excluded'] == 0 then
                if enemy_name_suffix ~= "" and v['name'] then
                    v['name'] = v['name'] .. enemy_name_suffix
                end
                table.insert(Lookups.locations, v)
                table.insert(Lookups.enemyLocations, v)
            end
        end
    end
end

function Lookups.Reset()
    Lookups.items = {}
    Lookups.locations = {}
    Lookups.itemLocations = {}
    Lookups.enemyLocations = {}
    Lookups.files = {}
    Lookups.typewriters = {}
    Lookups.regionConnections = {}
    Lookups.difficulty = nil
    Lookups.scenario = nil
end

return Lookups
