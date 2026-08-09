local DestroyObjects = {}
DestroyObjects.isInit = false
DestroyObjects.lastRemoval = os.time()
DestroyObjects.lastSafeRewardDestroy = 0

-- Downtown T-Junction patrol-car handgun ammo. Vanilla unlocks this when the
-- Fire Hose hydrant busts the Patrol Car Zombie out; randomizer leaves that
-- flag unset, so the placement stays Enabled and keeps the map room red.
-- Standard has no AP check here — just clear the stuck vanilla icon properly.
DestroyObjects.COP_CAR_AMMO = {
    item_object = "sm70_100",
    parent_object = "sm70_100_hgshell",
    folder_path = "RopewayContents/World/Location_DownTown/LocationLevel_DownTown/LocationFsm_DownTown/S03_1000/ES_S03_1000/Item/ES_S03_1000/I_200_T-Junction_Area",
    -- Stable ItemPositions.MyGuid for this placement (map-icon persistence).
    itemGuid = "22ba4633-f69f-41b8-89e0-09ac17a4a2b0",
}

function DestroyObjects.Init()
    if Archipelago.IsConnected() and not DestroyObjects.isInit then
        DestroyObjects.isInit = true
        DestroyObjects.lastRemoval = os.time()
        DestroyObjects.DestroyAll()
    end

    -- Opened safe rewards should poof quickly; don't wait on the 15s pass.
    -- Never run while SafeUI still needs TransmitCorrectAnswer.
    if Archipelago.IsConnected()
        and not (Items and Items.cancelNextSafeUI)
        and (Storage.dotSightSafe or Storage.hipPouchSafe or Storage.dualMagSafe)
        and os.clock() - DestroyObjects.lastSafeRewardDestroy >= 0.05
    then
        DestroyObjects.lastSafeRewardDestroy = os.clock()
        DestroyObjects.DestroyOpenedSafeRewards()
    end

    -- Re-run destroy pass every 15s. Must bump lastRemoval or isInit stays
    -- false forever after the first timeout and DestroyAll runs every frame
    -- (common hard-crash when connecting mid-game).
    if os.time() - DestroyObjects.lastRemoval > 15 then
        DestroyObjects.isInit = false
        DestroyObjects.lastRemoval = os.time()
    end
end

function DestroyObjects.DestroyGameObject(gameObject)
    if not gameObject then
        return
    end

    pcall(function()
        gameObject:call("destroy", gameObject)
    end)
end

-- Clear opened safe rewards with vanish/save so map icons stay gone.
-- Raw destroy() leaves SetItem Enable=true and the marker comes back.
function DestroyObjects.DestroyOpenedSafeRewards()
    if Items and Items.cancelNextSafeUI then
        return
    end

    local rewards = {}
    if Storage.dotSightSafe then
        table.insert(rewards, DestroyObjects.DotSight())
    end
    if Storage.hipPouchSafe then
        table.insert(rewards, DestroyObjects.HipPouch())
    end
    if Storage.dualMagSafe then
        table.insert(rewards, DestroyObjects.DualMag())
    end

    for _, reward in ipairs(rewards) do
        if reward then
            -- vanish/save clears map state; destroy removes the lingering mesh
            -- that vanish alone often leaves sitting in the open safe.
            DestroyObjects.ClearItemAndMap(reward)
            DestroyObjects.DestroyGameObject(reward)
        end
    end

    if Items and Items.RemoveStoredSafeMapIcons then
        Items.RemoveStoredSafeMapIcons(true)
    end
end

function DestroyObjects.GetItemPositions(itemObject)
    if not itemObject then
        return nil
    end

    local itemPositions = itemObject:call(
        "getComponent(System.Type)",
        sdk.typeof(sdk.game_namespace("item.ItemPositions"))
    )

    if not itemPositions then
        local transform = itemObject:call("get_Transform()")
        local parentTransform = transform and transform:call("get_Parent()")
        local parentObject = parentTransform and parentTransform:call("get_GameObject()")

        if parentObject then
            itemPositions = parentObject:call(
                "getComponent(System.Type)",
                sdk.typeof(sdk.game_namespace("item.ItemPositions"))
            )
        end
    end

    return itemPositions
end

local function parseGuid(str)
    if not str or str == "" then
        return nil
    end

    local typedef = sdk.find_type_definition("System.Guid")
    if not typedef then
        return nil
    end

    local parseMethod = typedef:get_method("Parse(System.String)")
    if not parseMethod then
        return nil
    end

    local ok, result = pcall(function()
        return parseMethod:call(nil, str)
    end)
    if ok then
        return result
    end

    return nil
end

local function getLocationId(name)
    local locType = sdk.find_type_definition(sdk.game_namespace("gamemastering.Location.ID"))
    if not locType then
        return nil
    end

    local field = locType:get_field(name)
    if not field then
        return nil
    end

    local ok, value = pcall(function()
        return field:get_data(nil)
    end)
    if ok then
        return value
    end

    return nil
end

-- Disable SetItem save + mark GUID so MapIcons drops the marker and the room
-- can go blue. No AP SendLocationCheck.
function DestroyObjects.DisableSetItemSave(itemGuid, locationId)
    if not itemGuid then
        return false
    end

    local itemManager = sdk.get_managed_singleton(
        sdk.game_namespace("gamemastering.ItemManager")
    )
    if not itemManager then
        return false
    end

    local disabled = false
    local locations = {}

    if locationId ~= nil then
        table.insert(locations, locationId)
    end

    local downtown = getLocationId("DownTown")
    if downtown ~= nil then
        table.insert(locations, downtown)
    end

    local current = nil
    pcall(function()
        current = Scene.getCurrentLocation()
    end)
    if current ~= nil then
        table.insert(locations, current)
    end

    for _, loc in ipairs(locations) do
        local saveData = nil
        pcall(function()
            saveData = itemManager:call("getSetItemSaveData", itemGuid, loc)
        end)
        if saveData then
            pcall(function()
                saveData:set_field("Enable", false)
            end)
            disabled = true
        end
    end

    return disabled
end

function DestroyObjects.ClearItemAndMap(itemObject)
    local itemPositions = DestroyObjects.GetItemPositions(itemObject)
    if not itemPositions then
        return false
    end

    pcall(function()
        itemPositions:call("vanishItemAndSave()")
    end)
    pcall(function()
        itemPositions:call("setCleared()")
    end)
    Storage.MarkCheckedItem(itemPositions)

    local itemGuid = nil
    pcall(function()
        itemGuid = itemPositions:get_field("MyGuid")
    end)
    DestroyObjects.DisableSetItemSave(itemGuid, nil)

    return true
end

function DestroyObjects.MarkCopCarAmmoGuidChecked()
    local guid = DestroyObjects.COP_CAR_AMMO.itemGuid
    if not guid or guid == "" or Storage.IsItemGuidChecked(guid) then
        return
    end

    Storage.checkedItemGuids[guid] = true
    Storage.Update()
end

function DestroyObjects.GetCopCarAmmoObject()
    local loc = DestroyObjects.COP_CAR_AMMO
    local child = DestroyObjects.GetObjectByLocation(
        "Item",
        loc.item_object,
        loc.parent_object,
        loc.folder_path
    )
    if child then
        return child
    end

    -- After vanishItemAndSave the child mesh is often gone; ItemPositions lives
    -- on the parent GO in this folder.
    for _, obj in pairs(DestroyObjects.GetObjectsWithTag("Item")) do
        if obj ~= nil then
            local object_name = obj:call("get_Name()")
            local object_folder = obj:call("get_Folder()")
            local object_folder_path = object_folder and object_folder:call("get_Path()")
            if object_name == loc.parent_object
                and object_folder_path == loc.folder_path
            then
                return obj
            end
        end
    end

    return nil
end

function DestroyObjects.ClearCopCarAmmo()
    -- Standard map clear only: vanish mesh + disable SetItem save + mark GUID
    -- so MapIcons stops drawing it and the room can turn blue.
    -- Never SendLocationCheck.
    local obj = DestroyObjects.GetCopCarAmmoObject()
    if obj then
        DestroyObjects.ClearItemAndMap(obj)
    end

    DestroyObjects.MarkCopCarAmmoGuidChecked()

    local knownGuid = parseGuid(DestroyObjects.COP_CAR_AMMO.itemGuid)
    if knownGuid then
        DestroyObjects.DisableSetItemSave(knownGuid, getLocationId("DownTown"))
    end

    if not Storage.downtownCopCarCleared then
        Storage.downtownCopCarCleared = true
        Storage.Update()
        log.info("[Randomizer] Cleared downtown patrol-car handgun ammo map placement")
    end

    return obj ~= nil
end

function DestroyObjects.DestroyAll()
    local destroyables = {
        DestroyObjects.GetPurposeGUI()
    }

    for _, obj in pairs(destroyables) do
        if obj ~= nil then
            DestroyObjects.DestroyGameObject(obj)
        end
    end

    DestroyObjects.DestroyOpenedSafeRewards()
    DestroyObjects.ClearCopCarAmmo()
end

function DestroyObjects.GetObjectsWithTag(tag_name)
    local scene = Scene.getSceneObject()
    if not scene then
        return {}
    end

    local objects = scene:call("findGameObjectsWithTag(System.String)", tag_name)

    if type(objects) ~= "table" then
        if objects and objects.get_elements then
            objects = objects:get_elements()
        else
            return {}
        end
    end

    return objects
end

function DestroyObjects.GetObjectByLocation(tag_name, item_object, parent_object, folder_path)
    local objects = DestroyObjects.GetObjectsWithTag(tag_name)

    for _, obj in pairs(objects) do
        if obj ~= nil then
            local object_name = obj:call("get_Name()")
            local object_folder = obj:call("get_Folder()")
            local object_folder_path = nil
            local object_parent_name = ""

            if object_folder ~= nil then
                object_folder_path = object_folder:call("get_Path()")
            end

            local object_transform = sdk.to_managed_object(obj:call("get_Transform()"))
            if object_transform ~= nil then
                local object_transform_parent = sdk.to_managed_object(object_transform:call("get_Parent()"))
                if object_transform_parent ~= nil then
                    local object_parent = sdk.to_managed_object(object_transform_parent:call("get_GameObject()"))
                    if object_parent ~= nil then
                        object_parent_name = object_parent:call("get_Name()") or ""
                    end
                end
            end

            if object_name == item_object
            and object_parent_name == (parent_object or "")
            and object_folder_path == folder_path then
                return obj
            end
        end
    end

    return nil
end

function DestroyObjects.GetPurposeGUI()
    local scene = Scene.getSceneObject()
    if not scene then
        return nil
    end

    return scene:call("findGameObject(System.String)", "GUI_Purpose")
end

function DestroyObjects.DotSight()
    local scene = Scene.getSceneObject()
    if not scene then
        return nil
    end

    return scene:call("findGameObject(System.String)", "sm71_001")
end

function DestroyObjects.HipPouch()
    return DestroyObjects.GetObjectByLocation(
        "Item",
        "sm74_200",
        "Pos_SafeBox_1FWOffice",
        "RopewayContents/World/Location_RPD/LocationLevel_RPD/LocationFsm_RPD/common/ES_common/1FW/WestOffice/IronSafe_1FWOffice"
    )
end

function DestroyObjects.DualMag()
    local scene = Scene.getSceneObject()
    if not scene then
        return nil
    end

    return scene:call("findGameObject(System.String)", "sm71_201")
end

return DestroyObjects
