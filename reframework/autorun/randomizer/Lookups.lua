local Lookups = {}

Lookups.filepath = Manifest.mod_name .. "/"
Lookups.items = {}
Lookups.all_items = {}
Lookups.locations = {}
Lookups.typewriters = {}
Lookups.character = nil
Lookups.scenario = nil
Lookups.difficulty = nil

function Lookups.Load(character, scenario, difficulty)
    -- If this was already loaded and not cleared, don't load again
    if #Lookups.items > 0 and #Lookups.locations > 0 then
        return
    end

    Lookups.character = character
    Lookups.scenario = scenario
    Lookups.difficulty = difficulty

    character = string.lower(character)
    scenario = string.lower(scenario)

    local jill_file = Lookups.filepath .. "/jill/items.json"
    local location_file = Lookups.filepath .. character .. "/" .. scenario .. "/locations.json"
    local location_hardcore_file = Lookups.filepath .. character .. "/" .. scenario .. "/locations_hardcore.json"
    local typewriter_file = Lookups.filepath .. character .. "/" .. scenario .. "/typewriters.json"

    Lookups.items = json.load_file(jill_file) or {}
    Lookups.locations = json.load_file(location_file) or {}
    Lookups.typewriters = json.load_file(typewriter_file) or {}

    -- have to check for hardcore file in case it's not there
    local hardcore_locations = json.load_file(location_hardcore_file) or {}

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
    Lookups.character = nil
    Lookups.scenario = nil
    Lookups.difficulty = nil
end

return Lookups
