--!strict

local ScreenRegistry = {}
ScreenRegistry.__index = ScreenRegistry

export type ScreenRegistry = typeof(setmetatable(
	{} :: {
		screens: { [string]: GuiObject },
		current: string?,
	},
	ScreenRegistry
))

function ScreenRegistry.new(): ScreenRegistry
	return setmetatable({ screens = {}, current = nil }, ScreenRegistry)
end

function ScreenRegistry.register(self: ScreenRegistry, name: string, screen: GuiObject)
	self.screens[name] = screen
	screen.Visible = false
end

function ScreenRegistry.open(self: ScreenRegistry, name: string)
	for screenName, screen in self.screens do
		screen.Visible = screenName == name
	end
	self.current = name
end

function ScreenRegistry.close(self: ScreenRegistry)
	for _, screen in self.screens do
		screen.Visible = false
	end
	self.current = nil
end

return ScreenRegistry
