local Lookups = {}

Lookups.filepath = Manifest.mod_name .. "/"
Lookups.items = {}
Lookups.locations = {}
Lookups.typewriters = {}
Lookups.character = nil
Lookups.scenario = nil

function Lookups.load(character, scenario)
    -- If this was already loaded and not cleared, don't load again
    if #Lookups.items > 0 and #Lookups.locations > 0 then
        return
    end

    Lookups.character = character
    Lookups.scenario = scenario

    character = string.lower(character)
    scenario = string.lower(scenario)

    local item_file = Lookups.filepath .. character .. "/items.json"
    local location_file = Lookups.filepath .. character .. "/" .. scenario .. "/locations.json"
    local typewriter_file = Lookups.filepath .. character .. "/" .. scenario .. "/typewriters.json"

    Lookups.items = json.load_file(item_file)
    Lookups.locations = json.load_file(location_file)
    Lookups.typewriters = json.load_file(typewriter_file)
end

function Lookups.clear()
    Lookups.items = {}
    Lookups.locations = {}
end

return Lookups
