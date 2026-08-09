-- AP location matching / checks / collect-out handling.

Archipelago.recentAlreadyCheckedWarn = Archipelago.recentAlreadyCheckedWarn or {}

-- Bumped whenever a location flips to sent, locally or from the server. Readers
-- that cache anything derived from loc.sent watch this so a checked location
-- stops being drawn on the next frame instead of on the next scan interval.
Archipelago.checkedStamp = Archipelago.checkedStamp or 0

function Archipelago.MarkLocationsChanged()
    Archipelago.checkedStamp = (Archipelago.checkedStamp or 0) + 1
end

-- sent by server when locations are checked (collect, etc.?)
function APLocationsCheckedHandler(locations_checked)
    return Archipelago.LocationsCheckedHandler(locations_checked)
end
AP_REF.on_location_checked = APLocationsCheckedHandler

function Archipelago.LocationsCheckedHandler(locations_checked)
    -- if we received locations that were collected out, mark them sent so we don't get anything from it
    for _, location_id in pairs(locations_checked) do
        local id = tonumber(location_id)
        if id ~= nil then
            Archipelago.hintedLocationIds[id] = nil
        end

        local translated = Archipelago._GetLocationFromLocationData(
            { id = id },
            true
        )

        if translated and translated.raw_data then
            translated.raw_data.sent = true
            Archipelago.MarkLocationsChanged()
            if translated.raw_data.name then
                Archipelago.hintedLocationNames[string.lower(translated.raw_data.name)] = nil
            end

            -- Persist file world-checks so reconnect/replay doesn't revive
            -- props the player already examined.
            if Files
                and Files.MarkWorldCollected
                and translated.raw_data.file_id
            then
                local fileId = tonumber(
                    string.match(tostring(translated.raw_data.file_id), "(%d+)$")
                )
                if fileId then
                    Files.MarkWorldCollected(fileId)
                end
            end
        end
    end
end

function Archipelago.IsItemLocation(location_data)
    location_data = Archipelago.SanitizeLocationData(location_data)
    local location = Archipelago._GetLocationFromLocationData(location_data, true) -- include_sent_locations

    if not location then
        return false
    end

    return true
end

function Archipelago.IsLocationRandomized(location_data)
    location_data = Archipelago.SanitizeLocationData(location_data)
    local location = Archipelago._GetLocationFromLocationData(location_data, true) -- include_sent_locations

    if not location then
        return false
    end
    
    if location['raw_data']['randomized'] == 0 and not location['raw_data']['force_item'] then
        return false
    end

    return true
end

function Archipelago.GetLocationName(location_data)
    location_data = Archipelago.SanitizeLocationData(location_data)
    local location = Archipelago._GetLocationFromLocationData(location_data, true) -- include_sent_locations

    if not location then
        return ""
    end

    return location["name"]
end

function Archipelago.CheckForVictoryLocation(location_data)
    location_data = Archipelago.SanitizeLocationData(location_data)
    local location = Archipelago._GetLocationFromLocationData(location_data)

    if location ~= nil and location["raw_data"]["victory"] then
        Archipelago.SendVictory()

        return true
    end
    
    return false
end

function Archipelago.SanitizeLocationData(location_data)
    -- remove any character in an item or parent name that is not a letter, number, space, or a handful of symbols
    if location_data['item_object'] then
        location_data['item_object'] = location_data['item_object']:gsub("[^A-Za-z0-9()'-_ ]", "")
    end
    if location_data['parent_object'] then
        location_data['parent_object'] = location_data['parent_object']:gsub("[^A-Za-z0-9()'-_ ]", "")
        -- Older captures/JSON used a literal "nil" montage segment when
        -- MontageID was missing ("4-158-0-18-nil"). Current data uses an
        -- empty trailing segment ("4-158-0-18-"). Accept both.
        location_data['parent_object'] = location_data['parent_object']:gsub("%-nil$", "-")
    end
    if location_data['object_guid'] then
        location_data['object_guid'] = string.lower(
            tostring(location_data['object_guid'])
        )
    end

    return location_data
end

-- Normalize "...-nil" vs "...-" montage segments before comparing parents.
function Archipelago._ParentObjectsMatch(a, b)
    if a == b then
        return true
    end
    if a == nil or b == nil then
        return false
    end

    local function norm(value)
        return tostring(value):gsub("%-nil$", "-")
    end

    return norm(a) == norm(b)
end

-- Off by default — the GUID miss toasts aren't useful for players testing.
-- Flip true if you need the "why didn't this match" breakdown again.
Archipelago.debugGuidMisses = false

-- Explains why a guid-keyed location failed to match. Either Lookups doesn't
-- have the live guid at all, or there's a tuple-compatible row with a different
-- stored guid (usual "wired capture doesn't match live" case).
function Archipelago.ExplainGuidMatchFailure(location_data)
    if not Archipelago.debugGuidMisses then
        return
    end

    location_data = Archipelago.SanitizeLocationData(location_data or {})
    local liveGuid = location_data['object_guid']
    if not liveGuid or liveGuid == "" then
        return
    end

    liveGuid = string.lower(tostring(liveGuid))
    local guidOwner = nil
    local tupleOwner = nil

    for _, loc in pairs(Lookups.locations or {}) do
        local locGuid = loc['object_guid']
        if locGuid and locGuid ~= ""
            and string.lower(tostring(locGuid)) == liveGuid
        then
            guidOwner = tostring(loc['region'] or "") .. " - " .. tostring(loc['name'] or "")
            break
        end
    end

    for _, loc in pairs(Lookups.locations or {}) do
        if location_data['item_object'] ~= nil
            and loc['item_object'] == location_data['item_object']
            and Archipelago._ParentObjectsMatch(
                loc['parent_object'],
                location_data['parent_object']
            )
            and loc['folder_path'] == location_data['folder_path']
        then
            tupleOwner = tostring(loc['region'] or "") .. " - " .. tostring(loc['name'] or "")
            local stored = loc['object_guid']
            if stored and stored ~= "" then
                tupleOwner = tupleOwner
                    .. " (json guid "
                    .. string.lower(tostring(stored))
                    .. ")"
            else
                tupleOwner = tupleOwner .. " (no json guid)"
            end
            break
        end
    end

    if guidOwner then
        GUI.AddTexts({
            { message="GUID matched ", color=AP_REF.HexToImguiColor("AAAAAA") },
            { message=guidOwner, color=AP_REF.HexToImguiColor("d9d904") },
            { message=" but was not sendable.", color=AP_REF.HexToImguiColor("AAAAAA") }
        })
        return
    end

    GUI.AddTexts({
        { message="GUID miss: ", color=AP_REF.HexToImguiColor("fa3d2f") },
        { message=liveGuid, color=AP_REF.HexToImguiColor("d9d904") }
    })
    if tupleOwner then
        GUI.AddTexts({
            { message="Tuple would be ", color=AP_REF.HexToImguiColor("AAAAAA") },
            { message=tupleOwner, color=AP_REF.HexToImguiColor("d9d904") },
            { message=" -- guid-keyed, no fallback.", color=AP_REF.HexToImguiColor("AAAAAA") }
        })
    else
        GUI.AddText("No Lookups row has this guid, and no tuple match either.")
    end
end

-- Returns:
--   - true if location was sent with no issues
--   - false if location was not sent because it has been sent prior
--   - nil if location was not sent because the AP call failed
function Archipelago.SendLocationCheck(location_data, warn_existing_location)
    if warn_existing_location == nil then
        warn_existing_location = true
    end

    location_data = Archipelago.SanitizeLocationData(location_data)

    -- Capture runtime GUID into the matching list under data/ArchipelagoRE3R/:
    --   _guid_captures_locations.json / _guid_captures_enemies.json / _guid_captures_files.json
    -- (doesn't change AP matching).
    if LocationCapture and location_data['object_guid'] then
        if location_data['file_id'] and not location_data['capture_kind'] then
            location_data['capture_kind'] = "files"
        end
        pcall(function()
            LocationCapture.Capture(location_data)
        end)
    end

    local location = Archipelago._GetLocationFromLocationData(location_data)
    local location_ids = {}

    if not location or not location['id'] or (location['id'] ~= nil and tonumber(location['id']) < 0) then
        -- if location wasn't found in session unsent locations, check all locations to make sure it's not a wrongly named location (indicating a version mismatch)
        -- if so, show a message; if not, just bail out of here since there's nothing to send
        local location_existing = Archipelago._GetLocationFromLocationData(location_data, true)

        if not location_existing or not location_existing['id'] or tonumber(location_existing['id']) < 0 then
            local attemptedName = location_existing and location_existing['name']
                or location_data['file_id']
                or location_data['object_guid']
                or location_data['item_object']
                or "unknown location"
            GUI.AddTexts({
                { message="Invalid location.", color=AP_REF.HexToImguiColor('fa3d2f') },
                { message=" You tried to check " },
                { message=attemptedName, color=AP_REF.HexToImguiColor("d9d904") },
                { message=", but it does not exist in the multiworld. " }
            })

            GUI.AddTexts({
                { message="Your apworld version and client version must match.", color=AP_REF.HexToImguiColor('fa3d2f') }
            })
        elseif warn_existing_location then
            -- File pickups hit getFile + openFile in one interact; only toast once.
            local warnKey = tostring(location_existing['name'] or location_existing['id'] or "")
            local now = os.clock()
            local lastWarn = Archipelago.recentAlreadyCheckedWarn[warnKey]
            if not lastWarn or (now - lastWarn) >= 2 then
                Archipelago.recentAlreadyCheckedWarn[warnKey] = now
                GUI.AddTexts({
                    { message="Location already checked or collected: ", color=AP_REF.HexToImguiColor("AAAAAA") },
                    { message=location_existing['name'] },
                    { message=".", color=AP_REF.HexToImguiColor("AAAAAA") }
                })
            end
        end

        return false
    end

    location_ids[1] = location["id"]

    local result = nil

    if Archipelago.IsConnected() then
        result = AP_REF.APClient.LocationChecks(AP_REF.APClient, location_ids)
    end

    if not result then
        return nil
    end

    local sent_loc = location['raw_data']    

    for k, loc in pairs(Lookups.locations) do
        local exact_match = true

        -- check that the location is an exact match of the location's raw data that came back from the lookup
        for lk, lv in pairs(sent_loc) do
            if not loc[lk] or loc[lk] ~= sent_loc[lk] then
                exact_match = false
                break -- if not, skip
            end
        end

        if exact_match then
            loc['sent'] = true
            break
        end
    end

    Archipelago.MarkLocationsChanged()

    return true
end

function Archipelago.SendVictory()
    AP_REF.APClient:StatusUpdate(AP_REF.AP.ClientStatus.GOAL)   
end

function Archipelago._GetLocationFromLocationData(location_data, include_sent_locations)
    local player = Archipelago.GetPlayer()

    include_sent_locations = include_sent_locations or false

    local translated_location = {}

    local scenario_suffix = ""
    local scenario_suffix_assisted = " (A)"
    local scenario_suffix_hardcore = " (H)"
    local scenario_suffix_nightmare = " (N)"
    local scenario_suffix_inferno = " (I)"

    if location_data['id'] and not location_data['name'] then
        location_data['name'] = AP_REF.APClient:get_location_name(location_data['id'], player['game'])
    end

    local function try_match(filter_fn, suffix)
        for _, loc in pairs(Lookups.locations) do
            if filter_fn(loc) then
                local location_name_with_region = loc['region'] .. suffix .. " - " .. loc['name']

                if location_data['name'] == location_name_with_region then
                    translated_location['name'] = location_name_with_region
                    translated_location['raw_data'] = loc
                    return true
                end

                if include_sent_locations or not loc['sent'] then
                    if (location_data['file_id'] ~= nil
                        and loc['file_id'] == location_data['file_id'])
                    then
                        translated_location['name'] = location_name_with_region
                        translated_location['raw_data'] = loc
                        return true
                    end

                    -- Prefer object_guid when present. GUID alone identifies the
                    -- placement; folder_path is not required to accept a guid hit
                    -- (requiring it silently broke garage checks after captures
                    -- were wired into JSON).
                    local dataGuid = location_data['object_guid']
                    local locGuid = loc['object_guid']
                    local hasDataGuid = dataGuid ~= nil and dataGuid ~= ""
                    local hasLocGuid = locGuid ~= nil and locGuid ~= ""
                    if hasDataGuid and hasLocGuid
                        and string.lower(tostring(dataGuid))
                            == string.lower(tostring(locGuid))
                    then
                        translated_location['name'] = location_name_with_region
                        translated_location['raw_data'] = loc
                        return true
                    end

                    -- Guid-keyed JSON rows are GUID-only. No tuple fallback --
                    -- otherwise a successful check after wiring captures does
                    -- not prove GUID matching works.
                    if not hasLocGuid
                        and location_data['item_object'] ~= nil
                        and loc['item_object'] == location_data['item_object']
                        and Archipelago._ParentObjectsMatch(
                            loc['parent_object'],
                            location_data['parent_object']
                        )
                        and loc['folder_path'] == location_data['folder_path']
                    then
                        translated_location['name'] = location_name_with_region
                        translated_location['raw_data'] = loc
                        return true
                    end
                end
            end
        end
        return false
    end

    local difficulty_map = {
        inferno = { flag = 'inferno', suffix = scenario_suffix_inferno },
        nightmare = { flag = 'nightmare', suffix = scenario_suffix_nightmare },
        hardcore = { flag = 'hardcore', suffix = scenario_suffix_hardcore },
        assisted = { flag = 'assisted', suffix = scenario_suffix_assisted },
    }

    local diff = difficulty_map[Lookups.difficulty]

    -- 1) First pass: match the looked-up difficulty's exclusive locations
    if diff then
        try_match(function(loc)
            return loc[diff.flag] ~= nil and loc[diff.flag]
        end, diff.suffix)
    end

    -- 2) Fallback: if not found, treat it as STANDARD
    if not translated_location['name'] then
        try_match(function(loc)
            return not (loc['assisted'] or loc['hardcore'] or loc['nightmare'] or loc['inferno'])
        end, scenario_suffix)
    end

    if not translated_location['name'] then
        return nil
    end

    translated_location['id'] = AP_REF.APClient:get_location_id(translated_location['name'], player['game'])

    return translated_location
end

function Archipelago.ResetLocationsState()
    Archipelago.recentAlreadyCheckedWarn = {}
end

return true
