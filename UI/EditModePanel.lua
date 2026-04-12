local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar

local EditModePanel = {}
addon.EditModePanel = EditModePanel

local PANEL_TITLE = "Sidecar Bar"
local PANEL_WIDTH = 385
local PANEL_HEIGHT = 192
local CONTENT_WIDTH = 343

local ICON_SIZE_MIN = 24
local ICON_SIZE_MAX = 72
local ICON_SIZE_STEP = 2

local SPACING_MIN = 0
local SPACING_MAX = 24
local SPACING_STEP = 1

local GROWTH_OPTIONS = {
	{ value = addon.Constants.GROWTH_LEFT, label = "Left" },
	{ value = addon.Constants.GROWTH_CENTER, label = "Center" },
	{ value = addon.Constants.GROWTH_RIGHT, label = "Right" },
}

local function ClampValue(value, minValue, maxValue)
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function RoundToStep(value, step)
	return math.floor((value / step) + 0.5) * step
end

local function GetMenuText(description)
	if MenuUtil and MenuUtil.GetElementText then
		return MenuUtil.GetElementText(description)
	end
	return description and description.text or nil
end

function EditModePanel:GetSelectedBar()
	if not self.selectedBarID or not addon.Profile then
		return nil
	end

	return addon.Profile:GetBarByID(self.selectedBarID)
end

function EditModePanel:GetGrowthLabel(direction)
	for _, option in ipairs(GROWTH_OPTIONS) do
		if option.value == direction then
			return option.label
		end
	end

	return "Right"
end

function EditModePanel:ApplyBarLayout(fields)
	local bar = self:GetSelectedBar()
	if not bar then
		self:Hide()
		return
	end

	addon.Profile:UpdateBarLayout(bar.id, fields)
	if addon.Bars then
		addon.Bars:RefreshRuntime()
	end
end

function EditModePanel:SetNumericField(field, value, minValue, maxValue, step)
	local bar = self:GetSelectedBar()
	if not bar then
		self:Hide()
		return
	end

	local clampedValue = ClampValue(RoundToStep(value, step), minValue, maxValue)
	if clampedValue == bar[field] then
		return
	end

	self:ApplyBarLayout({
		[field] = clampedValue,
	})
end

function EditModePanel:SetGrowthDirection(direction)
	local bar = self:GetSelectedBar()
	if not bar then
		self:Hide()
		return
	end

	if bar.growthDirection == direction then
		return
	end

	self:ApplyBarLayout({
		growthDirection = direction,
	})
end

function EditModePanel:ApplyDefaultAnchor()
	if not self.frame then
		return
	end

	self.frame:ClearAllPoints()
	if EditModeSystemSettingsDialog and EditModeSystemSettingsDialog:IsShown() then
		self.frame:SetPoint("TOPLEFT", EditModeSystemSettingsDialog, "TOPLEFT", 0, 0)
	else
		self.frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -250, 200)
	end
end

function EditModePanel:ShowForBar(barID)
	if not barID then
		self:Hide()
		return
	end

	self:EnsureUI()

	local wasShown = self.frame:IsShown()
	self.selectedBarID = barID
	if not wasShown or self.resetAnchorOnNextShow then
		self:ApplyDefaultAnchor()
		self.resetAnchorOnNextShow = false
	end

	self:Refresh()
	self.frame:Show()
end

function EditModePanel:Hide()
	self.selectedBarID = nil
	self.resetAnchorOnNextShow = true
	if self.frame then
		self.frame:Hide()
	end
end

function EditModePanel:Refresh()
	local frame = self.frame
	if not frame then
		return
	end

	local bar = self:GetSelectedBar()
	if not bar then
		self:Hide()
		return
	end

	frame.Title:SetText(bar.name or PANEL_TITLE)

	frame.SizeRow.isRefreshing = true
	frame.SizeRow.Slider:SetValue(bar.iconSize or 40)
	frame.SizeRow.isRefreshing = false

	frame.SpacingRow.isRefreshing = true
	frame.SpacingRow.Slider:SetValue(bar.spacing or 6)
	frame.SpacingRow.isRefreshing = false

	frame.GrowthRow.Dropdown:SetDefaultText(self:GetGrowthLabel(bar.growthDirection))
	frame.GrowthRow.Dropdown:GenerateMenu()
end

function EditModePanel:CreateSliderRow(parent, labelText, field, minValue, maxValue, step, valueFormatter)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(CONTENT_WIDTH, 32)

	row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	row.Label:SetSize(100, 32)
	row.Label:SetPoint("LEFT")
	row.Label:SetJustifyH("LEFT")
	row.Label:SetText(labelText)

	row.Slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	row.Slider:SetSize(200, 32)
	row.Slider:SetPoint("LEFT", row.Label, "RIGHT", 5, 0)
	row.Slider:Init(minValue, minValue, maxValue, (maxValue - minValue) / step, {
		[MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right, valueFormatter),
	})

	row.cbrHandles = EventUtil and EventUtil.CreateCallbackHandleContainer and EventUtil.CreateCallbackHandleContainer() or nil
	if row.cbrHandles then
		row.cbrHandles:RegisterCallback(row.Slider, MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
			if row.isRefreshing then
				return
			end

			EditModePanel:SetNumericField(field, value, minValue, maxValue, step)
		end)
	end

	return row
end

function EditModePanel:CreateGrowthRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(CONTENT_WIDTH, 32)

	row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	row.Label:SetSize(100, 32)
	row.Label:SetPoint("LEFT")
	row.Label:SetJustifyH("LEFT")
	row.Label:SetText("Growth Direction")

	row.Dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
	row.Dropdown:SetPoint("LEFT", row.Label, "RIGHT", 5, 0)
	row.Dropdown:SetWidth(225)
	row.Dropdown:SetSelectionText(function(selections)
		local selection = selections and selections[1]
		return selection and GetMenuText(selection) or nil
	end)
	row.Dropdown:SetDefaultText("Right")
	row.Dropdown:SetupMenu(function(dropdown, rootDescription)
		local bar = EditModePanel:GetSelectedBar()
		for _, option in ipairs(GROWTH_OPTIONS) do
			rootDescription:CreateRadio(option.label, function()
				return bar and bar.growthDirection == option.value
			end, function()
				EditModePanel:SetGrowthDirection(option.value)
			end)
		end
	end)

	return row
end

function EditModePanel:CreateUI()
	local frame = CreateFrame("Frame", "BuckleUpSidecarEditModePanel", UIParent)
	frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
	frame:SetFrameStrata("DIALOG")
	frame:SetFrameLevel(200)
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		EditModePanel.resetAnchorOnNextShow = false
	end)
	frame:Hide()

	frame.Border = CreateFrame("Frame", nil, frame, "DialogBorderTranslucentTemplate")
	frame.Border:SetAllPoints(frame)

	frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	frame.Title:SetPoint("TOP", 0, -15)
	frame.Title:SetText(PANEL_TITLE)

	frame.CloseButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.CloseButton:SetPoint("TOPRIGHT")
	frame.CloseButton:SetScript("OnClick", function()
		if addon.EditMode then
			addon.EditMode:ClearSelectedBarFrame(false)
		else
			EditModePanel:Hide()
		end
	end)

	frame.Settings = CreateFrame("Frame", nil, frame)
	frame.Settings:SetSize(CONTENT_WIDTH, 110)
	frame.Settings:SetPoint("TOP", frame.Title, "BOTTOM", 0, -12)

	frame.SizeRow = self:CreateSliderRow(frame.Settings, "Icon Size", "iconSize", ICON_SIZE_MIN, ICON_SIZE_MAX, ICON_SIZE_STEP, function(value)
		return string.format("%d px", value)
	end)
	frame.SizeRow:SetPoint("TOPLEFT")

	frame.SpacingRow = self:CreateSliderRow(frame.Settings, "Icon Spacing", "spacing", SPACING_MIN, SPACING_MAX, SPACING_STEP, function(value)
		return tostring(value)
	end)
	frame.SpacingRow:SetPoint("TOPLEFT", frame.SizeRow, "BOTTOMLEFT", 0, -6)

	frame.GrowthRow = self:CreateGrowthRow(frame.Settings)
	frame.GrowthRow:SetPoint("TOPLEFT", frame.SpacingRow, "BOTTOMLEFT", 0, -6)

	self.frame = frame
	self.resetAnchorOnNextShow = true
end

function EditModePanel:EnsureUI()
	if not self.frame then
		self:CreateUI()
	end

	return self.frame
end
