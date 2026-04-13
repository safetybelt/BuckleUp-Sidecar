local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar
local barPresentation = addon.BarPresentation

local EditModePanel = {}
addon.EditModePanel = EditModePanel

local PANEL_TITLE = "Sidecar Bar"
local PANEL_WIDTH = 385
local PANEL_HEIGHT = 320
local CONTENT_WIDTH = 343

local SIZE_MIN = 50
local SIZE_MAX = 200
local SIZE_STEP = 10

local PADDING_MIN = 0
local PADDING_MAX = 14
local PADDING_STEP = 1

local OPACITY_MIN = 50
local OPACITY_MAX = 100
local OPACITY_STEP = 1

local GROWTH_OPTIONS = {
	{ value = addon.Constants.GROWTH_LEFT, label = "Left" },
	{ value = addon.Constants.GROWTH_CENTER, label = "Center" },
	{ value = addon.Constants.GROWTH_RIGHT, label = "Right" },
}

local VISIBILITY_OPTIONS = {
	{ value = addon.Constants.BAR_VISIBILITY_ALWAYS, label = "Always" },
	{ value = addon.Constants.BAR_VISIBILITY_IN_COMBAT, label = "In Combat" },
	{ value = addon.Constants.BAR_VISIBILITY_HIDDEN, label = "Hidden" },
}

local MATCH_MODE_OPTIONS = {
	{ value = addon.Constants.BAR_MATCH_MANUAL, label = "Manual" },
	{ value = addon.Constants.BAR_MATCH_ESSENTIAL, label = "Match Essential Bar" },
	{ value = addon.Constants.BAR_MATCH_UTILITY, label = "Match Utility Bar" },
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

local function SetRowEnabled(row, enabled)
	row:SetAlpha(enabled and 1 or 0.45)
	row.isDisabled = not enabled
	if row.Slider and row.Slider.SetEnabled then
		row.Slider:SetEnabled(enabled)
	end
	if row.Dropdown and row.Dropdown.SetEnabled then
		row.Dropdown:SetEnabled(enabled)
	end
end

function EditModePanel:GetSelectedBar()
	if not self.selectedBarID or not addon.Profile then
		return nil
	end

	return addon.Profile:GetBarByID(self.selectedBarID)
end

function EditModePanel:GetEffectivePresentation(bar)
	if not bar or not addon.Profile then
		return nil
	end

	return barPresentation:Resolve(bar)
end

function EditModePanel:GetGrowthLabel(direction)
	for _, option in ipairs(GROWTH_OPTIONS) do
		if option.value == direction then
			return option.label
		end
	end

	return "Right"
end

function EditModePanel:GetVisibilityLabel(visibility)
	for _, option in ipairs(VISIBILITY_OPTIONS) do
		if option.value == visibility then
			return option.label
		end
	end

	return "Always"
end

function EditModePanel:GetMatchModeLabel(matchMode)
	for _, option in ipairs(MATCH_MODE_OPTIONS) do
		if option.value == matchMode then
			return option.label
		end
	end

	return "Manual"
end

function EditModePanel:IsFieldReadOnly(bar, field)
	return barPresentation and barPresentation:IsFieldReadOnly(bar, field) or false
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

	if self:IsFieldReadOnly(bar, field) then
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

function EditModePanel:SetVisibility(visibility)
	local bar = self:GetSelectedBar()
	if not bar then
		self:Hide()
		return
	end

	if self:IsFieldReadOnly(bar, "visibility") or bar.visibility == visibility then
		return
	end

	self:ApplyBarLayout({
		visibility = visibility,
	})
end

function EditModePanel:SetMatchMode(matchMode)
	local bar = self:GetSelectedBar()
	if not bar then
		self:Hide()
		return
	end

	if bar.matchMode == matchMode then
		return
	end

	self:ApplyBarLayout({
		matchMode = matchMode,
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

	local presentation = self:GetEffectivePresentation(bar)

	frame.Title:SetText(bar.name or PANEL_TITLE)

	frame.MatchRow.Dropdown:SetDefaultText(self:GetMatchModeLabel(bar.matchMode))
	frame.MatchRow.Dropdown:GenerateMenu()

	frame.SizeRow.isRefreshing = true
	frame.SizeRow.Slider:SetValue((presentation and presentation.sizePercent) or bar.sizePercent or addon.Constants.DEFAULT_BAR_SIZE_PERCENT)
	frame.SizeRow.isRefreshing = false
	SetRowEnabled(frame.SizeRow, not self:IsFieldReadOnly(bar, "sizePercent"))

	frame.PaddingRow.isRefreshing = true
	frame.PaddingRow.Slider:SetValue((presentation and presentation.padding) or bar.padding or addon.Constants.DEFAULT_BAR_PADDING)
	frame.PaddingRow.isRefreshing = false
	SetRowEnabled(frame.PaddingRow, not self:IsFieldReadOnly(bar, "padding"))

	frame.OpacityRow.isRefreshing = true
	frame.OpacityRow.Slider:SetValue((presentation and presentation.opacity) or bar.opacity or addon.Constants.DEFAULT_BAR_OPACITY)
	frame.OpacityRow.isRefreshing = false
	SetRowEnabled(frame.OpacityRow, not self:IsFieldReadOnly(bar, "opacity"))

	frame.VisibilityRow.Dropdown:SetDefaultText(self:GetVisibilityLabel((presentation and presentation.visibility) or bar.visibility))
	frame.VisibilityRow.Dropdown:GenerateMenu()
	SetRowEnabled(frame.VisibilityRow, not self:IsFieldReadOnly(bar, "visibility"))

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
			if row.isRefreshing or row.isDisabled then
				return
			end

			EditModePanel:SetNumericField(field, value, minValue, maxValue, step)
		end)
	end

	return row
end

function EditModePanel:CreateDropdownRow(parent, labelText, defaultText, options, isSelected, onSelect)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(CONTENT_WIDTH, 32)

	row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	row.Label:SetSize(100, 32)
	row.Label:SetPoint("LEFT")
	row.Label:SetJustifyH("LEFT")
	row.Label:SetText(labelText)

	row.Dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
	row.Dropdown:SetPoint("LEFT", row.Label, "RIGHT", 5, 0)
	row.Dropdown:SetWidth(225)
	row.Dropdown:SetSelectionText(function(selections)
		local selection = selections and selections[1]
		return selection and GetMenuText(selection) or nil
	end)
	row.Dropdown:SetDefaultText(defaultText)
	row.Dropdown:SetupMenu(function(_dropdown, rootDescription)
		for _, option in ipairs(options) do
			rootDescription:CreateRadio(option.label, function()
				return isSelected(option)
			end, function()
				if row.isDisabled then
					return
				end
				onSelect(option)
			end)
		end
	end)

	return row
end

function EditModePanel:CreateGrowthRow(parent)
	return self:CreateDropdownRow(parent, "Growth Direction", "Right", GROWTH_OPTIONS, function(option)
		local bar = EditModePanel:GetSelectedBar()
		return bar and bar.growthDirection == option.value
	end, function(option)
		EditModePanel:SetGrowthDirection(option.value)
	end)
end

function EditModePanel:CreateVisibilityRow(parent)
	return self:CreateDropdownRow(parent, "Visibility", "Always", VISIBILITY_OPTIONS, function(option)
		local bar = EditModePanel:GetSelectedBar()
		local presentation = EditModePanel:GetEffectivePresentation(bar)
		return (presentation and presentation.visibility or (bar and bar.visibility)) == option.value
	end, function(option)
		EditModePanel:SetVisibility(option.value)
	end)
end

function EditModePanel:CreateMatchRow(parent)
	return self:CreateDropdownRow(parent, "Match Mode", "Manual", MATCH_MODE_OPTIONS, function(option)
		local bar = EditModePanel:GetSelectedBar()
		return bar and bar.matchMode == option.value
	end, function(option)
		EditModePanel:SetMatchMode(option.value)
	end)
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
	frame.Settings:SetSize(CONTENT_WIDTH, 235)
	frame.Settings:SetPoint("TOP", frame.Title, "BOTTOM", 0, -12)

	frame.MatchRow = self:CreateMatchRow(frame.Settings)
	frame.MatchRow:SetPoint("TOPLEFT")

	frame.SizeRow = self:CreateSliderRow(frame.Settings, "Size", "sizePercent", SIZE_MIN, SIZE_MAX, SIZE_STEP, function(value)
		return string.format("%d%%", value)
	end)
	frame.SizeRow:SetPoint("TOPLEFT", frame.MatchRow, "BOTTOMLEFT", 0, -6)

	frame.PaddingRow = self:CreateSliderRow(frame.Settings, "Padding", "padding", PADDING_MIN, PADDING_MAX, PADDING_STEP, function(value)
		return tostring(value)
	end)
	frame.PaddingRow:SetPoint("TOPLEFT", frame.SizeRow, "BOTTOMLEFT", 0, -6)

	frame.OpacityRow = self:CreateSliderRow(frame.Settings, "Opacity", "opacity", OPACITY_MIN, OPACITY_MAX, OPACITY_STEP, function(value)
		return string.format("%d%%", value)
	end)
	frame.OpacityRow:SetPoint("TOPLEFT", frame.PaddingRow, "BOTTOMLEFT", 0, -6)

	frame.VisibilityRow = self:CreateVisibilityRow(frame.Settings)
	frame.VisibilityRow:SetPoint("TOPLEFT", frame.OpacityRow, "BOTTOMLEFT", 0, -6)

	frame.GrowthRow = self:CreateGrowthRow(frame.Settings)
	frame.GrowthRow:SetPoint("TOPLEFT", frame.VisibilityRow, "BOTTOMLEFT", 0, -6)

	self.frame = frame
	self.resetAnchorOnNextShow = true
end

function EditModePanel:EnsureUI()
	if not self.frame then
		self:CreateUI()
	end

	return self.frame
end
