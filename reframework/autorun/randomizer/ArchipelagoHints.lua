-- AP hint storage / ItemIndicator highlighting.

Archipelago.hintedLocationIds = Archipelago.hintedLocationIds or {}
Archipelago.hintedLocationNames = Archipelago.hintedLocationNames or {}
Archipelago.hintedLocationGuids = Archipelago.hintedLocationGuids or {}
Archipelago.hintedFileIds = Archipelago.hintedFileIds or {}
Archipelago.hintsRetryAt = Archipelago.hintsRetryAt

local function hint_truthy(value)
    return value == true or value == 1 or value == "true" or value == "1"
end

-- Lookups uses short names; AP uses "Region [(diff)] - Name".
local function location_ap_name_candidates(loc)
    local names = {}
    if not loc or type(loc.name) ~= "string" or loc.name == "" then
        return names
    end
    table.insert(names, loc.name)
    if type(loc.region) == "string" and loc.region ~= "" then
        local suffixes = { "", " (A)", " (H)", " (N)", " (I)" }
        if Lookups and Lookups.difficulty then
            local prefer = {
                assisted = " (A)",
                hardcore = " (H)",
                nightmare = " (N)",
                inferno = " (I)",
            }
            local first = prefer[Lookups.difficulty]
            if first then
                suffixes = { first, "", " (A)", " (H)", " (N)", " (I)" }
            end
        end
        local seen = {}
        for _, suffix in ipairs(suffixes) do
            local full = loc.region .. suffix .. " - " .. loc.name
            local key = string.lower(full)
            if not seen[key] then
                seen[key] = true
                table.insert(names, full)
            end
        end
    end
    return names
end

function Archipelago.HintsStorageKey()
    if AP_REF.APClient == nil then
        return nil
    end
    local team = nil
    local slot = nil
    pcall(function()
        team = AP_REF.APClient:get_team_number()
        slot = AP_REF.APClient:get_player_number()
    end)
    if team == nil or slot == nil or tonumber(slot) < 0 then
        return nil
    end
    return string.format("_read_hints_%s_%s", tostring(team), tostring(slot))
end

function Archipelago.ClearHints()
    Archipelago.hintedLocationIds = {}
    Archipelago.hintedLocationNames = {}
    Archipelago.hintedLocationGuids = {}
    Archipelago.hintedFileIds = {}
end

function Archipelago.ApplyHintsList(hints)
    Archipelago.ClearHints()
    if type(hints) ~= "table" or AP_REF.APClient == nil then
        return
    end

    local me = nil
    pcall(function()
        me = tonumber(AP_REF.APClient:get_player_number())
    end)
    if me == nil then
        return
    end

    local game = nil
    pcall(function()
        game = AP_REF.APClient:get_player_game(me)
    end)

    local count = 0
    for _, hint in pairs(hints) do
        if type(hint) == "table" then
            local finding = tonumber(hint.finding_player or hint["finding_player"])
            local found = hint.found
            if found == nil then
                found = hint["found"]
            end
            local locationId = tonumber(hint.location or hint["location"])
            if finding == me and not hint_truthy(found) and locationId ~= nil then
                Archipelago.hintedLocationIds[locationId] = true
                count = count + 1

                local name = nil
                pcall(function()
                    if game ~= nil then
                        name = AP_REF.APClient:get_location_name(locationId, game)
                    else
                        name = AP_REF.APClient:get_location_name(locationId)
                    end
                end)
                if type(name) == "string" and name ~= "" then
                    Archipelago.hintedLocationNames[string.lower(name)] = true
                end

                -- Resolve to Lookups row so ItemIndicator can match by GUID.
                local translated = nil
                pcall(function()
                    translated = Archipelago._GetLocationFromLocationData(
                        { id = locationId, name = name },
                        true
                    )
                end)
                if translated and translated.raw_data then
                    local raw = translated.raw_data
                    if type(raw.object_guid) == "string" and raw.object_guid ~= "" then
                        Archipelago.hintedLocationGuids[string.lower(raw.object_guid)] = true
                    end
                    if raw.file_id then
                        local fileId = tonumber(string.match(tostring(raw.file_id), "(%d+)$"))
                        if fileId then
                            Archipelago.hintedFileIds[fileId] = true
                        end
                    end
                    if type(raw.name) == "string" and raw.name ~= "" then
                        Archipelago.hintedLocationNames[string.lower(raw.name)] = true
                    end
                end
            end
        end
    end
    log.info("[Randomizer] Applied " .. tostring(count) .. " unfound hint location(s)")
end

function Archipelago.RequestHints()
    if not Archipelago.IsConnected() then
        return
    end
    local key = Archipelago.HintsStorageKey()
    if not key then
        return
    end
    log.info("[Randomizer] Requesting hints key=" .. key)
    local getOk = false
    pcall(function()
        getOk = AP_REF.APClient:Get({ key }) == true
    end)
    if not getOk then
        -- Some builds want varargs / bare string.
        pcall(function()
            AP_REF.APClient:Get(key)
        end)
    end
    pcall(function()
        AP_REF.APClient:SetNotify({ key })
    end)
end

function Archipelago.IsLocationHinted(loc)
    if not loc then
        return false
    end
    if not next(Archipelago.hintedLocationIds)
        and not next(Archipelago.hintedLocationGuids)
        and not next(Archipelago.hintedFileIds)
    then
        return false
    end

    local id = tonumber(loc.id or loc.location_id)
    if id ~= nil and Archipelago.hintedLocationIds[id] then
        return true
    end

    local guid = loc.object_guid
    if type(guid) == "string" and guid ~= "" then
        if Archipelago.hintedLocationGuids[string.lower(guid)] then
            return true
        end
    end

    if loc.file_id then
        local fileId = tonumber(string.match(tostring(loc.file_id), "(%d+)$"))
        if fileId and Archipelago.hintedFileIds[fileId] then
            return true
        end
    end

    for _, candidate in ipairs(location_ap_name_candidates(loc)) do
        if Archipelago.hintedLocationNames[string.lower(candidate)] then
            return true
        end
        if AP_REF.APClient ~= nil then
            local resolved = nil
            pcall(function()
                local player = Archipelago.GetPlayer()
                if player.game then
                    resolved = AP_REF.APClient:get_location_id(candidate, player.game)
                else
                    resolved = AP_REF.APClient:get_location_id(candidate)
                end
            end)
            resolved = tonumber(resolved)
            if resolved ~= nil and Archipelago.hintedLocationIds[resolved] then
                return true
            end
        end
    end

    return false
end

-- retry hint fetch shortly after connect; first Get can race RoomInfo/slot
function Archipelago.HintsTick()
    if Archipelago.hintsRetryAt and os.clock() >= Archipelago.hintsRetryAt then
        Archipelago.hintsRetryAt = nil
        if Archipelago.IsConnected() and not next(Archipelago.hintedLocationIds) then
            Archipelago.RequestHints()
        end
    end
end

function Archipelago.RetrievedHandler(map, keys, extra)
    local hintKey = Archipelago.HintsStorageKey()
    if not hintKey then
        return
    end

    local hints = nil
    if type(map) == "table" then
        hints = map[hintKey]
        -- Some clients flatten / nest oddly; scan keys for our hint key.
        if hints == nil and type(keys) == "table" then
            for _, k in pairs(keys) do
                if k == hintKey and map[k] ~= nil then
                    hints = map[k]
                    break
                end
            end
        end
    end

    if hints ~= nil then
        Archipelago.ApplyHintsList(hints)
    elseif type(keys) == "table" then
        for _, k in pairs(keys) do
            if k == hintKey then
                -- Explicit nil/empty from server.
                Archipelago.ClearHints()
                break
            end
        end
    end
end

function Archipelago.SetReplyHandler(message)
    if type(message) ~= "table" then
        return
    end
    local hintKey = Archipelago.HintsStorageKey()
    local key = message.key or message["key"]
    if hintKey and key == hintKey then
        local value = message.value
        if value == nil then
            value = message["value"]
        end
        if value == nil then
            value = message.data or message["data"]
        end
        Archipelago.ApplyHintsList(value or {})
    end
end

local function APRetrievedHandler(map, keys, extra)
    return Archipelago.RetrievedHandler(map, keys, extra)
end
AP_REF.on_retrieved = APRetrievedHandler

local function APSetReplyHandler(message)
    return Archipelago.SetReplyHandler(message)
end
AP_REF.on_set_reply = APSetReplyHandler

return true
