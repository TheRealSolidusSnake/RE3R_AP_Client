local Helpers = {}

-- getting transform children is kinda annoying, so here's a helper for it
function Helpers.get_children(xform)
	local children = {}
	local child = xform:call("get_Child")
	while child do 
		table.insert(children, child)
		child = child:call("get_Next")
	end
	return children[1] and children
end

return Helpers