local Lookups = {}

Lookups.filepath = Manifest.mod_name .. "/"
Lookups.items = {}
Lookups.all_items = {}
Lookups.locations = {}
Lookups.typewriters = {}
Lookups.difficulty = nil

function Lookups.Load(difficulty)
    -- If this was already loaded and not cleared, don't load again
    if #Lookups.items > 0 and #Lookups.locations > 0 then
        return
    end

    Lookups.difficulty = difficulty

    local item_file = Lookups.filepath .. "/items.json"
    local location_file = Lookups.filepath .. "/locations.json"
    local location_hardcore_file = Lookups.filepath .. "/locations_hardcore.json"
    local location_nightmare_file = Lookups.filepath .. "/locations_nightmare.json"
    local location_inferno_file = Lookups.filepath .. "/locations_inferno.json"
    local typewriter_file = Lookups.filepath .. "/typewriters.json"

    Lookups.items = json.load_file(item_file) or {}
    Lookups.locations = json.load_file(location_file) or {}
    Lookups.typewriters = json.load_file(typewriter_file) or {}

    -- have to check for nightmare/hardcore/inferno files
    local inferno_locations = json.load_file(location_inferno_file) or {}
    local nightmare_locations = json.load_file(location_nightmare_file) or {}
    local hardcore_locations = json.load_file(location_hardcore_file) or {}

    if inferno_locations then
        for k, v in pairs(inferno_locations) do
            if not v['remove'] then -- ignore "remove" locations because they're for generation only
                v['inferno'] = true
                table.insert(Lookups.locations, v)
            end
        end
    end

    if nightmare_locations then
        for k, v in pairs(nightmare_locations) do
            if not v['remove'] then -- ignore "remove" locations because they're for generation only
                v['nightmare'] = true
                table.insert(Lookups.locations, v)
            end
        end
    end

    if hardcore_locations then
        for k, v in pairs(hardcore_locations) do
            if not v['remove'] then -- ignore "remove" locations because they're for generation only
                v['hardcore'] = true
                table.insert(Lookups.locations, v)
            end
        end
    end
end

function Lookups.Reset()
    Lookups.items = {}
    Lookups.locations = {}
    Lookups.typewriters = {}
    Lookups.difficulty = nil
end

return Lookups
