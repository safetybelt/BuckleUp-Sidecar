local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar
local util = addon.Util
local constants = addon.Constants

local BarPresentation = {}
addon.BarPresentation = BarPresentation

-- This module is the narrow compatibility layer between Sidecar's stored bar settings
-- and the live presentation we render. It intentionally owns Blizzard cooldown viewer
-- matching and the small amount of viewer-specific layout math needed for visual parity,
-- so Profile can stay focused on persisted state and migration.

local function ClampValue(value, minValue, maxValue)
	if value == nil then
		return minValue
	end
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

function BarPresentation:NormalizeVisibility(value)
	if value == constants.BAR_VISIBILITY_ALWAYS
		or value == constants.BAR_VISIBILITY_IN_COMBAT
		or value == constants.BAR_VISIBILITY_HIDDEN then
		return value
	end
	return constants.BAR_VISIBILITY_ALWAYS
end

function BarPresentation:NormalizeMatchMode(value)
	if value == constants.BAR_MATCH_ESSENTIAL or value == constants.BAR_MATCH_UTILITY then
		return value
	end
	return constants.BAR_MATCH_MANUAL
end

function BarPresentation:NormalizeStoredFields(bar)
	local source = bar or {}

	return {
		sizePercent = ClampValue(util.NumberOrNil(source.sizePercent) or constants.DEFAULT_BAR_SIZE_PERCENT, 50, 200),
		padding = ClampValue(util.NumberOrNil(source.padding) or constants.DEFAULT_BAR_PADDING, 0, 14),
		opacity = ClampValue(util.NumberOrNil(source.opacity) or constants.DEFAULT_BAR_OPACITY, 50, 100),
		visibility = self:NormalizeVisibility(source.visibility),
		matchMode = self:NormalizeMatchMode(source.matchMode),
	}
end

function BarPresentation:EnsureCooldownViewerLoaded()
	if _G.EssentialCooldownViewer or _G.UtilityCooldownViewer then
		return true
	end

	if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
		C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
	elseif type(UIParentLoadAddOn) == "function" then
		UIParentLoadAddOn("Blizzard_CooldownViewer")
	end

	return _G.EssentialCooldownViewer ~= nil or _G.UtilityCooldownViewer ~= nil
end

function BarPresentation:GetMatchFrame(matchMode)
	local normalizedMatchMode = self:NormalizeMatchMode(matchMode)
	if normalizedMatchMode == constants.BAR_MATCH_ESSENTIAL then
		self:EnsureCooldownViewerLoaded()
		return _G.EssentialCooldownViewer
	end
	if normalizedMatchMode == constants.BAR_MATCH_UTILITY then
		self:EnsureCooldownViewerLoaded()
		return _G.UtilityCooldownViewer
	end
	return nil
end

function BarPresentation:GetMatchedSettings(matchMode)
	local frame = self:GetMatchFrame(matchMode)
	if not frame or type(frame.GetSettingValue) ~= "function" or type(Enum) ~= "table" or not Enum.EditModeCooldownViewerSetting then
		return nil
	end

	local useDisplayValue = false
	local visibility = frame:GetSettingValue(Enum.EditModeCooldownViewerSetting.VisibleSetting, useDisplayValue)
	if visibility == Enum.CooldownViewerVisibleSetting.InCombat then
		visibility = constants.BAR_VISIBILITY_IN_COMBAT
	elseif visibility == Enum.CooldownViewerVisibleSetting.Hidden then
		visibility = constants.BAR_VISIBILITY_HIDDEN
	else
		visibility = constants.BAR_VISIBILITY_ALWAYS
	end

	return {
		sizePercent = ClampValue(frame:GetSettingValue(Enum.EditModeCooldownViewerSetting.IconSize, useDisplayValue) or constants.DEFAULT_BAR_SIZE_PERCENT, 50, 200),
		padding = ClampValue(frame:GetSettingValue(Enum.EditModeCooldownViewerSetting.IconPadding, useDisplayValue) or constants.DEFAULT_BAR_PADDING, 0, 14),
		opacity = ClampValue(frame:GetSettingValue(Enum.EditModeCooldownViewerSetting.Opacity, useDisplayValue) or constants.DEFAULT_BAR_OPACITY, 50, 100),
		visibility = visibility,
	}
end

function BarPresentation:IsFieldReadOnly(bar, field)
	if not bar then
		return false
	end

	local matchMode = self:NormalizeMatchMode(bar.matchMode)
	if matchMode == constants.BAR_MATCH_MANUAL then
		return false
	end

	return field == "sizePercent"
		or field == "padding"
		or field == "opacity"
		or field == "visibility"
end

function BarPresentation:Resolve(bar)
	if not bar then
		return nil
	end

	local resolved = self:NormalizeStoredFields(bar)
	local matchedSettings = self:GetMatchedSettings(resolved.matchMode)
	if matchedSettings then
		resolved.sizePercent = matchedSettings.sizePercent
		resolved.padding = matchedSettings.padding
		resolved.opacity = matchedSettings.opacity
		resolved.visibility = matchedSettings.visibility
	end

	local baselineIconSize = constants.ESSENTIAL_BASE_ICON_SIZE
	if resolved.matchMode == constants.BAR_MATCH_UTILITY then
		baselineIconSize = constants.UTILITY_BASE_ICON_SIZE or baselineIconSize
	end

	local sizeScale = resolved.sizePercent / 100
	-- Blizzard cooldown viewers present a user-facing padding value but lay icons out
	-- with a tighter internal stride. Sidecar mirrors that here instead of leaking the
	-- heuristic into runtime layout or saved profile data.
	local interIconSpacing = (resolved.padding + (constants.BLIZZARD_COOLDOWN_VIEWER_PADDING_OFFSET or 0)) * sizeScale

	resolved.baselineIconSize = baselineIconSize
	resolved.iconSize = baselineIconSize * sizeScale
	resolved.spacing = resolved.padding
	resolved.interIconSpacing = interIconSpacing
	resolved.outerPadding = math.max(0, interIconSpacing)
	return resolved
end
