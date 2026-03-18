local DestroyObjects = {}
DestroyObjects.isInit = false
DestroyObjects.lastRemoval = os.time()

function DestroyObjects.Init()
    if Archipelago.IsConnected() and not DestroyObjects.isInit then
        DestroyObjects.isInit = true
        DestroyObjects.DestroyAll()
    end

    -- Reset the init flag every 15 seconds
    if os.time() - DestroyObjects.lastRemoval > 15 then -- 15 seconds
        DestroyObjects.isInit = false
    end
end

function DestroyObjects.DestroyAll()
    local destroyables = {
        DestroyObjects.GetPurposeGUI(),
	DestroyObjects.DotSight(),
	DestroyObjects.HipPouch(),
	DestroyObjects.DualMag()
    }

    -- if we opened the first safe, remove the Dot Sight
    if Storage.dotSightSafe then
        table.insert(destroyables, DestroyObjects.DotSight())
    end

    -- if we opened the second safe, remove the Hip Pouch
    if Storage.hipPouchSafe then
        table.insert(destroyables, DestroyObjects.HipPouch())
    end

    -- if we opened the third safe, remove the Dual Mag
    if Storage.dualMagSafe then
        table.insert(destroyables, DestroyObjects.DualMag())
    end

    for _, obj in pairs(destroyables) do
        if obj ~= nil then
            obj:call("destroy", obj)
        end
    end
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
    return scene:call("findGameObject(System.String)", "GUI_Purpose")
end

function DestroyObjects.DotSight()
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
    return scene:call("findGameObject(System.String)", "sm71_201")
end

return DestroyObjects