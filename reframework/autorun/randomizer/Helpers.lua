local Helpers = {}

function Helpers.gameObject(obj_name)
    local scene = Scene.getSceneObject()
    if not scene then
        return nil
    end

    return scene:call("findGameObject(System.String)", obj_name)
end

function Helpers.component(obj, component_namespace)
    return obj:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace(component_namespace)))
end

-- A sibling chain that loops back on itself would hang the game thread here,
-- so the walk is capped rather than trusted to terminate.
Helpers.MAX_CHAIN_WALK = 20000

-- getting transform children is kinda annoying, so here's a helper for it
function Helpers.get_children(xform)
	local children = {}
	local child = xform:call("get_Child")
	local seen = {}
	local steps = 0

	while child do
		local address = child.get_address and child:get_address() or nil
		if address and seen[address] then
			log.warn("[Helpers] get_children: cycle detected after "
				.. tostring(steps) .. " sibling(s); stopping walk")
			break
		end
		if address then
			seen[address] = true
		end

		table.insert(children, child)

		steps = steps + 1
		if steps >= Helpers.MAX_CHAIN_WALK then
			log.warn("[Helpers] get_children: hit walk cap of "
				.. tostring(Helpers.MAX_CHAIN_WALK) .. "; stopping walk")
			break
		end

		child = child:call("get_Next")
	end

	return children[1] and children
end

function Helpers.wait(seconds) 
    local start = os.time() 
    repeat until os.time() > start + seconds 
end

return Helpers