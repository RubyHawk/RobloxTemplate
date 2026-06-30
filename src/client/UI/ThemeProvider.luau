--!strict

-- Resolves a pack's theme by deep-merging its partial override (Theme.packs[themeId])
-- over the frozen base tokens into a fresh working copy. Callers read the result
-- with the same shape as Theme (.colors/.radius/.spacing/.font), so it is a
-- drop-in replacement for `require(Shared.Theme)`.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Template"):WaitForChild("Shared")
local Theme = require(Shared.Theme)
local TableMerge = require(Shared.TableMerge)

local ThemeProvider = {}

function ThemeProvider.resolve(themeId: string?): any
	local overrides = nil
	if themeId ~= nil and themeId ~= "" then
		overrides = (Theme :: any).packs[themeId]
	end
	return TableMerge.deep(Theme, overrides)
end

-- Safe color-token lookup: returns the named token, then the fallback token, then
-- the theme's text color, so a typo in a binding can never error the HUD.
function ThemeProvider.color(resolved: any, name: string?, fallback: string?): Color3
	local colors = resolved.colors
	if name ~= nil and colors[name] then
		return colors[name]
	end
	if fallback ~= nil and colors[fallback] then
		return colors[fallback]
	end
	return colors.text
end

return ThemeProvider
