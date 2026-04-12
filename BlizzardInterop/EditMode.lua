local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar

local EditMode = {}
addon.EditMode = EditMode

local function EnsureEditModeLoaded()
	if EditModeManagerFrame then
		return true
	end

	if type(UIParentLoadAddOn) == "function" then
		UIParentLoadAddOn("Blizzard_EditMode")
	end

	return EditModeManagerFrame ~= nil
end

function EditMode:IsActive()
	return EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() or false
end

function EditMode:CanBarBeDragged(barID)
	if addon.EditModePlacement then
		return addon.EditModePlacement:CanBarBeDragged(barID)
	end

	return self:IsActive()
end

function EditMode:ApplyBarAnchor(barFrame, bar)
	if addon.EditModePlacement then
		addon.EditModePlacement:ApplyBarAnchor(barFrame, bar)
	end
end

function EditMode:SaveBarAnchor(barID, barFrame)
	if addon.EditModePlacement then
		addon.EditModePlacement:SaveBarAnchor(barID, barFrame)
	end
end

function EditMode:ApplyKnownTargetAlignment(barFrame)
	if addon.EditModePlacement then
		addon.EditModePlacement:ApplyKnownTargetAlignment(barFrame)
	end
end

function EditMode:ReapplyBarAnchor(barFrame, barID)
	if addon.EditModePlacement then
		addon.EditModePlacement:ReapplyStoredAnchor(barFrame, barID)
	end
end

function EditMode:SelectBarFrame(barFrame)
	if addon.EditModeSelection then
		addon.EditModeSelection:SelectBarFrame(barFrame)
	end
end

function EditMode:ClearSelectedBarFrame(keepPanelOpen)
	if addon.EditModeSelection then
		addon.EditModeSelection:ClearSelectedBarFrameSelection(keepPanelOpen)
	end
end

function EditMode:ShowPanelForBar(barFrame)
	if addon.EditModeSelection then
		addon.EditModeSelection:ShowPanelForBar(barFrame)
	end
end

function EditMode:HidePanel()
	if addon.EditModeSelection then
		addon.EditModeSelection:HidePanel()
	end
end

function EditMode:AttachBarFrame(barFrame)
	if addon.EditModePlacement then
		addon.EditModePlacement:AttachBarFrame(barFrame)
	end

	if addon.EditModeSelection then
		addon.EditModeSelection:EnsureSelectionFrame(barFrame)
	end
end

function EditMode:RefreshBarFrame(barFrame)
	if not barFrame then
		return
	end

	self:AttachBarFrame(barFrame)
	if addon.EditModeSelection then
		addon.EditModeSelection:RefreshBarFrame(barFrame, self:IsActive())
	end
end

function EditMode:OnEditModeEnter()
	if not addon.barFrames then
		return
	end

	self.selectedBarFrame = nil
	for _, barFrame in pairs(addon.barFrames) do
		if barFrame:IsShown() then
			self:AttachBarFrame(barFrame)
			if addon.EditModeSelection then
				addon.EditModeSelection:RefreshBarFrame(barFrame, true)
			end
		end
	end

	self:HidePanel()
	if addon.Bars then
		addon.Bars:RefreshRuntime()
	end
end

function EditMode:OnEditModeExit()
	if not addon.barFrames then
		return
	end

	for _, barFrame in pairs(addon.barFrames) do
		if barFrame.isDragging then
			barFrame:StopMovingOrSizing()
			barFrame.isDragging = false
		end

		if addon.EditModeSelection then
			addon.EditModeSelection:ClearBarSelection(barFrame)
		end
		barFrame.isEditModeActive = false
		self:SaveBarAnchor(barFrame.barID, barFrame)
	end

	if EditModeManagerFrame and EditModeManagerFrame.ClearSnapPreviewFrame then
		EditModeManagerFrame:ClearSnapPreviewFrame()
	end

	self.selectedBarFrame = nil
	self:HidePanel()
	if addon.Bars then
		addon.Bars:RefreshRuntime()
	end
end

function EditMode:HandleExternalSelectionChange(selectedSystem)
	if addon.EditModeSelection then
		addon.EditModeSelection:HandleExternalSelectionChange(selectedSystem)
	end
end

function EditMode:Initialize()
	if self.initialized then
		return
	end

	if not EnsureEditModeLoaded() then
		return
	end

	if not self.callbacksRegistered and EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
		EventRegistry:RegisterCallback("EditMode.Enter", function()
			EditMode:OnEditModeEnter()
		end, self)
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			EditMode:OnEditModeExit()
		end, self)
		self.callbacksRegistered = true
	end

	if not self.selectionHooksInstalled and hooksecurefunc and EditModeManagerFrame then
		if type(EditModeManagerFrame.SelectSystem) == "function" then
			hooksecurefunc(EditModeManagerFrame, "SelectSystem", function(manager, selectedSystem)
				EditMode:HandleExternalSelectionChange(selectedSystem or manager.selectedSystem)
			end)
		end
		if type(EditModeManagerFrame.ClearSelectedSystem) == "function" then
			hooksecurefunc(EditModeManagerFrame, "ClearSelectedSystem", function(manager)
				EditMode:HandleExternalSelectionChange(manager and manager.selectedSystem)
			end)
		end
		self.selectionHooksInstalled = true
	end

	self.initialized = true
	if self:IsActive() then
		self:OnEditModeEnter()
	end
end
