local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar
local util = addon.Util
local constants = addon.Constants

local EditModePlacement = {}
addon.EditModePlacement = EditModePlacement

local SIDECAR_EDIT_MODE_SYSTEM_BASE = 9100
local BAR_PADDING = constants.BAR_PADDING or 4
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
	if frame and frame.isSidecarBarFrame then
		-- Sidecar-to-Sidecar snaps intentionally use the same cross-axis cleanup as
		-- Blizzard cooldown viewers so linked bars read like one continuous extension.
		return true
	end

	local frameName = GetPointFrameName(frame)
	return frameName and CENTER_ALIGNMENT_TARGETS[frameName] == true
end

local function GetHorizontalAnchorDirection(point)
	if not point then
		return 0
	end

	if string.find(point, "LEFT", 1, true) then
		return -1
	end

	if string.find(point, "RIGHT", 1, true) then
		return 1
	end

	return 0
end

local function GetAnchorPointX(point, width)
	local direction = GetHorizontalAnchorDirection(point)
	if direction < 0 then
		return 0
	end

	if direction > 0 then
		return width
	end

	return width / 2
end

local function GetPinnedVisualX(barFrame, bar)
	if not barFrame or not bar then
		return 0
	end

	local width = util.NumberOrNil(barFrame.GetWidth and barFrame:GetWidth()) or 0
	if width <= 0 then
		return 0
	end

	local growthDirection = bar.growthDirection or constants.GROWTH_RIGHT
	local iconSize = util.NumberOrNil(bar.iconSize) or 40

	if growthDirection == constants.GROWTH_LEFT then
		return width - BAR_PADDING - (iconSize / 2)
	end

	if growthDirection == constants.GROWTH_CENTER then
		return width / 2
	end

	return BAR_PADDING + (iconSize / 2)
end

local function GetVisualAnchorOffsetX(barFrame, bar, point)
	if not barFrame or not bar then
		return 0
	end

	local width = util.NumberOrNil(barFrame.GetWidth and barFrame:GetWidth()) or 0
	if width <= 0 then
		return 0
	end

	return GetPinnedVisualX(barFrame, bar) - GetAnchorPointX(point, width)
end

function EditModePlacement:CanBarBeDragged(_barID)
	return addon.EditMode and addon.EditMode:IsActive() or false
end

function EditModePlacement:ApplyBarAnchor(barFrame, bar)
	if not barFrame or not bar then
		return
	end

	local point = bar.point or "CENTER"
	-- Saved x/y represent the pinned visual reference for the current growth mode,
	-- not the raw frame edge. We convert between that visual point and the frame anchor
	-- symmetrically on load/save so size and spacing changes do not make the bar walk.
	local offsetX = GetVisualAnchorOffsetX(barFrame, bar, point)

	barFrame:ClearAllPoints()
	if bar.relativeTo then
		barFrame:SetPoint(
			point,
			ResolveRelativeFrame(bar.relativeTo),
			bar.relativePoint or point,
			(bar.x or 0) - offsetX,
			bar.y or 0
		)
	end
end

function EditModePlacement:SaveBarAnchor(barID, barFrame)
	local bar = addon.Profile and addon.Profile:GetBarByID(barID)
	if not bar or not barFrame or not barFrame.GetPoint then
		return
	end

	local point, relativeTo, relativePoint, offsetX, offsetY = barFrame:GetPoint(1)
	if not point then
		return
	end

	offsetX = (offsetX or 0) + GetVisualAnchorOffsetX(barFrame, bar, point)

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

function EditModePlacement:ApplyKnownTargetAlignment(barFrame)
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

function EditModePlacement:AttachBarFrame(barFrame)
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

	barFrame.sidecarEditModeAttached = true
end

function EditModePlacement:ReapplyStoredAnchor(barFrame, barID)
	if not barFrame or not barID or addon.isDraggingBar and addon.isDraggingBar[barID] then
		return
	end

	local bar = addon.Profile and addon.Profile:GetBarByID(barID)
	if not bar then
		return
	end

	self:ApplyBarAnchor(barFrame, bar)
end
