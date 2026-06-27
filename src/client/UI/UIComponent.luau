--!strict

export type Handle = {
	root: GuiObject,
	setVisible: (boolean) -> (),
	destroy: () -> (),
}

local UIComponent = {}

function UIComponent.mount(parent: Instance, builder: (Instance) -> GuiObject): Handle
	local root = builder(parent)
	return {
		root = root,
		setVisible = function(visible: boolean)
			root.Visible = visible
		end,
		destroy = function()
			root:Destroy()
		end,
	}
end

return UIComponent
