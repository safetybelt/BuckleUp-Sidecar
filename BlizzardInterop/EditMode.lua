local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar
local util = addon.Util
local constants = addon.Constants

local EditMode = {}
addon.EditMode = EditMode

local SIDECAR_EDIT_MODE_SYSTEM_BASE = 9100
local CENTER_ALIGNMENT_TARGETS = {
	EssentialCooldownViewer = true,
	UtilityCooldownViewer = true,
	BuffIconCooldownViewer = true,
	BuffBarCooldownViewer = true,
}

local function EnsureEditModeLoaded()
	if EditModeManagerFrame then
		return true
	end

	if type(UIParentLoadAddOn) == "function" then
		UIParentLoadAddOn("Blizzard_EditMode")
	end

	return EditModeManagerFrame ~= nil
end

local function ResolveRelativeFrame(frameName)
	if not frameName or frameName == "" or frameName == "UIParent" then
		return UIParent
	end

	return _G[frameName] or UIParent
end

local function GetPointFrameName(frame)
	return frame and frame.GetName and frame:GetName() or nil
end

local function IsCenterAlignmentTarget(frame)
	local frameName = GetPointFrameName(frame)
	return frameName and CENTER_ALIGNMENT_TARGETS[frameName] == true
end

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

local function HighlightBarFrame(barFrame)
	local selection = EnsureSelectionFrame(barFrame)
	barFrame:SetMovable(false)
	barFrame:AnchorSelectionFrame()
	selection:ShowHighlighted()
	barFrame.isHighlighted = true
	barFrame.isSelected = false
	UpdateMagnetismRegistration(barFrame)
end

local function ClearBarSelection(barFrame)
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

function EditMode:IsActive()
	return EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() or false
end

function EditMode:CanBarBeDragged(barID)
	return self:IsActive()
end

function EditMode:ApplyBarAnchor(barFrame, bar)
	if not barFrame or not bar then
		return
	end

	barFrame:ClearAllPoints()
	if bar.relativeTo then
		barFrame:SetPoint(
			bar.point or "CENTER",
			ResolveRelativeFrame(bar.relativeTo),
			bar.relativePoint or bar.point or "CENTER",
			bar.x or 0,
			bar.y or 0
		)
	end
end

function EditMode:SaveBarAnchor(barID, barFrame)
	local bar = addon.Profile and addon.Profile:GetBarByID(barID)
	if not bar or not barFrame or not barFrame.GetPoint then
		return
	end

	local point, relativeTo, relativePoint, offsetX, offsetY = barFrame:GetPoint(1)
	if not point then
		return
	end

	local snappedToFrame = barFrame.snappedToFrame
	if (not relativeTo or relativeTo == UIParent) and snappedToFrame then
		relativeTo = snappedToFrame
	end

	local relativeToName = relativeTo and relativeTo.GetName and relativeTo:GetName() or "UIParent"
	local layout = {
		point = point,
		relativePoint = relativePoint,
		relativeTo = relativeToName,
		x = util.NumberOrNil(offsetX) or 0,
		y = util.NumberOrNil(offsetY) or 0,
	}

	addon.Profile:UpdateBarLayout(barID, layout)
end

function EditMode:ApplyKnownTargetAlignment(barFrame)
	if not barFrame or not barFrame.GetPoint then
		return
	end

	local point, relativeTo, relativePoint, offsetX, offsetY = barFrame:GetPoint(1)
	if not point then
		return
	end

	if (not relativeTo or relativeTo == UIParent) and barFrame.snappedToFrame then
		relativeTo = barFrame.snappedToFrame
	end

	if not IsCenterAlignmentTarget(relativeTo) then
		return
	end

	local adjustedX = offsetX or 0
	local adjustedY = offsetY or 0
	if (point == "LEFT" and relativePoint == "RIGHT") or (point == "RIGHT" and relativePoint == "LEFT") then
		adjustedY = 0
	elseif (point == "TOP" and relativePoint == "BOTTOM") or (point == "BOTTOM" and relativePoint == "TOP") then
		adjustedX = 0
	elseif point == "CENTER" and relativePoint == "CENTER" then
		adjustedX = 0
		adjustedY = 0
	else
		return
	end

	if adjustedX == offsetX and adjustedY == offsetY then
		return
	end

	barFrame:ClearAllPoints()
	barFrame:SetPoint(point, relativeTo, relativePoint, adjustedX, adjustedY)
end

function EditMode:SelectBarFrame(barFrame)
	if not barFrame then
		return
	end

	if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
		EditModeManagerFrame:ClearSelectedSystem()
	end

	if self.selectedBarFrame and self.selectedBarFrame ~= barFrame then
		HighlightBarFrame(self.selectedBarFrame)
	end

	local selection = EnsureSelectionFrame(barFrame)
	barFrame:SetMovable(true)
	barFrame:AnchorSelectionFrame()
	selection:ShowSelected()
	barFrame.isHighlighted = true
	barFrame.isSelected = true
	self.selectedBarFrame = barFrame
	UpdateMagnetismRegistration(barFrame)
end

function EditMode:AttachBarFrame(barFrame)
	if not barFrame or barFrame.sidecarEditModeAttached then
		return
	end

	if not EnsureEditModeLoaded() or not EditModeSystemMixin then
		return
	end

	-- This is intentionally a narrow compatibility shim, not a full Blizzard-owned
	-- Edit Mode system. We borrow the mixin's snap bookkeeping overrides so Sidecar
	-- bars can participate in native magnetism, but Sidecar still owns placement
	-- persistence and does not register as a real Blizzard Edit Mode system.
	Mixin(barFrame, EditModeSystemMixin)
	if not barFrame.SetPointBase then
		barFrame.SetPointBase = barFrame.SetPoint
		barFrame.SetPoint = barFrame.SetPointOverride
	end
	if not barFrame.ClearAllPointsBase then
		barFrame.ClearAllPointsBase = barFrame.ClearAllPoints
		barFrame.ClearAllPoints = barFrame.ClearAllPointsOverride
	end
	barFrame.snappedFrames = barFrame.snappedFrames or {}
	barFrame.system = SIDECAR_EDIT_MODE_SYSTEM_BASE + (tonumber(tostring(barFrame.barID):match("(%d+)")) or 0)
	barFrame.systemNameString = "Sidecar"

	function barFrame:GetSystemName()
		return self.systemNameString
	end

	EnsureSelectionFrame(barFrame)
	barFrame.sidecarEditModeAttached = true
	if self:IsActive() then
		self:RefreshBarFrame(barFrame)
	end
end

function EditMode:RefreshBarFrame(barFrame)
	if not barFrame then
		return
	end

	self:AttachBarFrame(barFrame)
	if self:IsActive() then
		barFrame.isEditModeActive = true
		HighlightBarFrame(barFrame)
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

function EditMode:OnEditModeEnter()
	if not addon.barFrames then
		return
	end

	self.selectedBarFrame = nil
	for _, barFrame in pairs(addon.barFrames) do
		if barFrame:IsShown() then
			self:AttachBarFrame(barFrame)
			barFrame.isEditModeActive = true
			HighlightBarFrame(barFrame)
		end
	end
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
		barFrame.isEditModeActive = false
		ClearBarSelection(barFrame)
		self:SaveBarAnchor(barFrame.barID, barFrame)
	end

	if EditModeManagerFrame and EditModeManagerFrame.ClearSnapPreviewFrame then
		EditModeManagerFrame:ClearSnapPreviewFrame()
	end

	self.selectedBarFrame = nil
	if addon.Bars then
		addon.Bars:RefreshRuntime()
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

	self.initialized = true
	if self:IsActive() then
		self:OnEditModeEnter()
	end
end
