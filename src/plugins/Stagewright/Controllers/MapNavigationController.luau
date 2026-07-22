--!strict

local ProjectStore = require(script.Parent.Parent.ProjectStore)

local MapNavigationController = {}

export type Callbacks = {
	cancelInteraction: () -> (),
	focusPlayable: () -> boolean,
	focusAdmin: () -> boolean,
	reportBlocked: (string) -> (),
	setStatus: (string, boolean?) -> (),
}

function MapNavigationController.bind(
	playableButton: TextButton,
	adminButton: TextButton,
	callbacks: Callbacks
)
	playableButton.Activated:Connect(function()
		callbacks.cancelInteraction()
		local focused = callbacks.focusPlayable()
		callbacks.setStatus(
			if focused then "Focused the first playable grid." else "The playable grid could not be resolved.",
			not focused
		)
	end)
	adminButton.Activated:Connect(function()
		if not ProjectStore.isWritable() then
			callbacks.reportBlocked("Focus authoring area")
			return
		end
		callbacks.cancelInteraction()
		local focused = callbacks.focusAdmin()
		callbacks.setStatus(
			if focused
				then "Focused the Stagewright admin work area."
				else "The admin work area could not be found.",
			not focused
		)
	end)
end

return table.freeze(MapNavigationController)
