local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar

local EditModeSelection = {}
addon.EditModeSelection = EditModeSelection

local function EnsureSelectionFrame(barFrame)
	if barFrame.Selection then
		return barFrame.Selection
	end

	local selection = CreateFrame("Frame", nil, barFrame, "EditModeSystemSelectionTemplate")
	selection:ClearAllPoints()
	selection:SetAllPoints(barFrame)
	selection:SetFrameStrata("TOOLTIP")
	selection:SetFrameLevel(barFrame:GetFrameLevel() + 10)
	selection:EnableMouse(false)
	selection:SetSystem(barFrame)
	selection:Hide()

	barFrame.Selection = selection
	return selection
end

local function UpdateMagnetismRegistration(barFrame)
	if not barFrame or not EditModeMagnetismManager then
		return
	end

	if barFrame:IsVisible() and barFrame.isEditModeActive and barFrame.isHighlighted and not barFrame.isSelected then
		EditModeMagnetismManager:RegisterFrame(barFrame)
	else
		EditModeMagnetismManager:UnregisterFrame(barFrame)
	end
end

function EditModeSelection:EnsureSelectionFrame(barFrame)
	return EnsureSelectionFrame(barFrame)
end

function EditModeSelection:HighlightBarFrame(barFrame)
	if not barFrame then
		return
	end

	local selection = EnsureSelectionFrame(barFrame)
	barFrame:SetMovable(false)
	barFrame:AnchorSelectionFrame()
	selection:ShowHighlighted()
	barFrame.isHighlighted = true
	barFrame.isSelected = false
	UpdateMagnetismRegistration(barFrame)
end

function EditModeSelection:ShowSelectedBarFrame(barFrame)
	if not barFrame then
		return
	end

	local selection = EnsureSelectionFrame(barFrame)
	barFrame:SetMovable(true)
	barFrame:AnchorSelectionFrame()
	selection:ShowSelected()
	barFrame.isHighlighted = true
	barFrame.isSelected = true
	UpdateMagnetismRegistration(barFrame)
end

function EditModeSelection:ClearBarSelection(barFrame)
	if not barFrame then
		return
	end

	local selection = EnsureSelectionFrame(barFrame)
	selection:Hide()
	barFrame.isHighlighted = false
	barFrame.isSelected = false
	barFrame.isDragging = false
	barFrame:SetMovable(false)
	UpdateMagnetismRegistration(barFrame)
end

function EditModeSelection:ShowPanelForBar(barFrame)
	if addon.EditModePanel then
		addon.EditModePanel:ShowForBar(barFrame and barFrame.barID)
	end
end

function EditModeSelection:HidePanel()
	if addon.EditModePanel then
		addon.EditModePanel:Hide()
	end
end

function EditModeSelection:ClearSelectedBarFrameSelection(keepPanelOpen)
	local editMode = addon.EditMode
	if not editMode or not editMode.selectedBarFrame then
		if not keepPanelOpen then
			self:HidePanel()
		end
		return
	end

	self:ClearBarSelection(editMode.selectedBarFrame)
	editMode.selectedBarFrame = nil
	if not keepPanelOpen then
		self:HidePanel()
	end
end

function EditModeSelection:DemoteSelectedBarFrameToHighlight(keepPanelOpen)
	local editMode = addon.EditMode
	if not editMode or not editMode.selectedBarFrame then
		if not keepPanelOpen then
			self:HidePanel()
		end
		return
	end

	if editMode:IsActive() then
		self:HighlightBarFrame(editMode.selectedBarFrame)
	else
		self:ClearBarSelection(editMode.selectedBarFrame)
	end
	editMode.selectedBarFrame = nil
	if not keepPanelOpen then
		self:HidePanel()
	end
end

function EditModeSelection:SelectBarFrame(barFrame)
	local editMode = addon.EditMode
	if not editMode or not barFrame then
		return
	end

	if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
		editMode.suppressExternalSelectionClear = true
		EditModeManagerFrame:ClearSelectedSystem()
		editMode.suppressExternalSelectionClear = false
	end

	if editMode.selectedBarFrame and editMode.selectedBarFrame ~= barFrame then
		self:HighlightBarFrame(editMode.selectedBarFrame)
	end

	self:ShowSelectedBarFrame(barFrame)
	editMode.selectedBarFrame = barFrame
	self:ShowPanelForBar(barFrame)
end

function EditModeSelection:RefreshBarFrame(barFrame, isActive)
	if not barFrame then
		return
	end

	EnsureSelectionFrame(barFrame)
	if isActive then
		barFrame.isEditModeActive = true
		if addon.EditMode and addon.EditMode.selectedBarFrame == barFrame then
			self:ShowSelectedBarFrame(barFrame)
		else
			self:HighlightBarFrame(barFrame)
		end
	else
		barFrame.isEditModeActive = false
		if barFrame.Selection then
			barFrame.Selection:Hide()
		end
		barFrame.isHighlighted = false
		barFrame.isSelected = false
		barFrame.isDragging = false
		UpdateMagnetismRegistration(barFrame)
	end
end

function EditModeSelection:HandleExternalSelectionChange(selectedSystem)
	local editMode = addon.EditMode
	if not editMode or editMode.suppressExternalSelectionClear or not editMode:IsActive() then
		return
	end

	if selectedSystem and selectedSystem.isSidecarBarFrame then
		if editMode.selectedBarFrame ~= selectedSystem then
			editMode.selectedBarFrame = selectedSystem
		end
		self:ShowSelectedBarFrame(selectedSystem)
		self:ShowPanelForBar(selectedSystem)
		return
	end

	self:DemoteSelectedBarFrameToHighlight(false)
end
