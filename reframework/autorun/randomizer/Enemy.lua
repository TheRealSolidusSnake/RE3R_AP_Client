local Enemy = {}

Enemy.isInit = false -- keeps track of whether init things like hook need to run
Enemy.debug = false -- set true to dump kill snippets for enemies.json authoring

function Enemy.Init()
    if Enemy.isInit then
        return
    end

    Enemy.isInit = true
    Enemy.SetupEnemyDeadHook()
end

-- RE3 port of the RE2 enemy-kill location hook.
--
-- Notes:
-- * The underlying RE Engine types can vary between titles/versions.
-- * This hook is written defensively: if the type/method isn't found, it simply does nothing.
-- * When Enemy.debug = true, it will print a JSON-ish snippet to help you build enemies.json entries.
function Enemy.SetupEnemyDeadHook()
    local hpType = sdk.find_type_definition(sdk.game_namespace("EnemyController"))
    if hpType == nil then
        -- Some builds may namespace this differently; try a couple fallbacks.
        hpType = sdk.find_type_definition(sdk.game_namespace("enemy.EnemyController"))
    end
    if hpType == nil then
        log.debug("[Enemy] EnemyController type not found; enemy-kill locations will be disabled.")
        return
    end

    local dead_method = hpType:get_method("applyDead")
    if dead_method == nil then
        log.debug("[Enemy] EnemyController.applyDead not found; enemy-kill locations will be disabled.")
        return
    end

    sdk.hook(dead_method, function(args)
        local ok, err = pcall(function()
            local compEnemy = sdk.to_managed_object(args[2])
            if compEnemy == nil then
                return
            end

            local goEnemy = sdk.to_managed_object(compEnemy:call("get_GameObject"))
            if goEnemy == nil then
                return
            end

            -- Try to build a stable-ish identifier (ported from RE2).
            local occComp = compEnemy:get_field("<OwnerContextController>k__BackingField")
            local ownerContext = compEnemy:get_field("<OwnerContext>k__BackingField")
            local initialKind = nil
            local montageId = nil

            if occComp ~= nil then
                initialKind = occComp:get_field("InitialKind")
            end

            if ownerContext ~= nil then
                montageId = ownerContext:call("get_MontageID")
            end

            local kindValue = initialKind
            if type(initialKind) == "userdata" then
                local okRaw, raw = pcall(function()
                    return initialKind:get_field("value__")
                end)
                if okRaw and raw ~= nil then
                    kindValue = raw
                end
            end

            local item_name = goEnemy:call("get_Name()")
            local item_folder = goEnemy:call("get_Folder()")
            local item_folder_path = nil
            if item_folder then
                item_folder_path = item_folder:call("get_Path()")
            end

            -- These Assign* calls exist in RE2; guard them for RE3.
            local assignLoc = nil
            local assignMap = nil
            local assignArea = nil

            local okAssign = pcall(function()
                assignLoc = compEnemy:call("get_AssignLocationID")
                assignMap = compEnemy:call("get_AssignMapID")
                assignArea = compEnemy:call("get_AssignAreaID")
            end)

            -- MontageID is often nil for dogs / some spawns. tostring(nil) is
            -- the literal "nil", which used to match older enemies.json rows
            -- ("...-18-nil") but current data uses a trailing empty segment
            -- ("...-18-"). Prefer empty string so both dogs match again.
            local montageStr = ""
            if montageId ~= nil then
                montageStr = tostring(montageId)
            end

            local item_parent_name = nil
            if okAssign and assignLoc ~= nil and assignMap ~= nil and assignArea ~= nil then
                item_parent_name = tostring(assignLoc) .. "-" .. tostring(assignMap) .. "-" .. tostring(assignArea) .. "-" .. tostring(kindValue) .. "-" .. montageStr
            else
                -- Fallback: still include kind/montage in case that's all we get.
                item_parent_name = tostring(kindValue) .. "-" .. montageStr
            end

            local object_guid = nil
            pcall(function()
                local contextGuid = compEnemy:call("get_ContextGUID")
                if contextGuid and Storage and Storage.GetGuidString then
                    object_guid = Storage.GetGuidString(contextGuid)
                    if object_guid == "" then
                        object_guid = nil
                    end
                end
            end)

            if Enemy.debug then
                local snippet = "---- DEAD ENEMY ----\n{\n"
                    .. "\t\"name\": \"\",\n"
                    .. "\t\"region\": \"\",\n"
                    .. "\t\"original_item\": \"\",\n"
                    .. "\t\"object_guid\": \"" .. tostring(object_guid or "") .. "\",\n"
                    .. "\t\"item_object\": \"" .. tostring(item_name) .. "\",\n"
                    .. "\t\"parent_object\": \"" .. tostring(item_parent_name) .. "\",\n"
                    .. "\t\"folder_path\": \"" .. tostring(item_folder_path) .. "\"\n},"
                log.info(snippet)
                pcall(function()
                    json.dump_file(
                        Manifest.mod_name .. "/_enemy_kill_debug.json",
                        {
                            name = "",
                            region = "",
                            original_item = "",
                            object_guid = object_guid,
                            item_object = item_name,
                            parent_object = item_parent_name,
                            folder_path = item_folder_path,
                            time = os.time(),
                        }
                    )
                end)
            end

            local location_to_check = {
                item_object = item_name,
                parent_object = item_parent_name,
                folder_path = item_folder_path,
                object_guid = object_guid
            }

            if LocationCapture and object_guid then
                location_to_check.capture_kind = "enemies"
                pcall(function()
                    LocationCapture.Capture(location_to_check)
                end)
            end

            -- nothing to do with AP if not connected
            if not Archipelago.IsConnected() then
                if Archipelago.hasConnectedPrior then
                    GUI.AddText("Archipelago is not connected.")
                end
                return
            end

            -- Only send a check if this kill matches an AP location.
            -- Never toast "already checked" for enemies — respawns re-fire
            -- applyDead and that message is noise in combat.
            if Archipelago.IsItemLocation(location_to_check) then
                local sent = Archipelago.SendLocationCheck(
                    location_to_check,
                    false
                )
                Archipelago.waitingForInvincibilityOff = true

                if sent == nil then
                    GUI.AddText("Enemy kill location did not send (connection issue). Verify your AP room and try again.")
                    return
                end
                if sent == false and location_to_check.object_guid then
                    -- Already checked, or guid-keyed miss with no warn flag.
                    local existing = Archipelago._GetLocationFromLocationData(
                        location_to_check,
                        true
                    )
                    if not existing then
                        Archipelago.ExplainGuidMatchFailure(location_to_check)
                    end
                end
            elseif location_to_check.object_guid then
                Archipelago.ExplainGuidMatchFailure(location_to_check)
            end
        end)

        if not ok then
            log.debug("[Enemy] applyDead hook error: " .. tostring(err))
        end
    end)
end

return Enemy
