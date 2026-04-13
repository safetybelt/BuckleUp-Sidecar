local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar
local util = addon.Util
local constants = addon.Constants
local barPresentation = addon.BarPresentation
local skin = addon.CooldownViewerSkin
local readiness = addon.Readiness
local spellDisplayState = addon.SpellDisplayState
local editMode = addon.EditMode

local Bars = {}
addon.Bars = Bars
addon.isDraggingBar = addon.isDraggingBar or {}

local LARGE_COOLDOWN_FONT = "GameFontHighlightHugeOutline"
local SMALL_COOLDOWN_FONT = "GameFontHighlightOutline"

local function CreateBackdrop(frame)
	if frame.SetBackdrop then
		frame:SetBackdrop(nil)
	end
end

local function ApplyStoredBarPlacement(barFrame, bar)
	if editMode then
		editMode:ApplyBarAnchor(barFrame, bar)
	end
end

local function CanDragBarFrame(barID)
	if editMode then
		return editMode:CanBarBeDragged(barID)
	end
	return false
end

local function PersistDraggedBarPlacement(barID, frame)
	if editMode then
		editMode:SaveBarAnchor(barID, frame)
	end
end

local function ShouldBarBeShown(barFrame, bar, entries)
	if editMode and editMode:IsActive() then
		return true
	end

	if not bar or not addon.Profile then
		return false
	end

	local presentation = barPresentation:Resolve(bar)
	if not presentation then
		return false
	end

	if #entries == 0 then
		return false
	end

	if presentation.visibility == constants.BAR_VISIBILITY_HIDDEN then
		return false
	end

	if presentation.visibility == constants.BAR_VISIBILITY_IN_COMBAT then
		return UnitAffectingCombat("player") == true
	end

	return true
end

local function ApplyBarPresentation(barFrame, bar, entries)
	if not barFrame or not bar then
		return
	end

	local presentation = barPresentation and barPresentation:Resolve(bar)
	local alpha = presentation and ((presentation.opacity or constants.DEFAULT_BAR_OPACITY) / 100) or 1
	barFrame:SetAlpha(alpha)
	barFrame:SetShown(ShouldBarBeShown(barFrame, bar, entries))
end

local function ResetCooldown(button)
	button.Cooldown:Clear()
	button.Cooldown:SetDrawSwipe(false)
	button.Cooldown:Hide()
end

local function UpdateButtonDesaturation(button)
	if not button or not button.Icon or not button.entry then
		return
	end

	local shouldDesaturate = button.baseShouldDesaturate == true
	if not shouldDesaturate and (button.entry.kind == "spell" or button.entry.kind == "racial") then
		shouldDesaturate = spellDisplayState and spellDisplayState:ShouldDesaturate(
			button.entry.spellID,
			button.Cooldown,
			button.cooldownFrameCountsForDesaturation
		) or false
	end

	if button.lastShouldDesaturate == shouldDesaturate then
		return
	end

	button.lastShouldDesaturate = shouldDesaturate
	button.Icon:SetDesaturated(shouldDesaturate)
	button.Icon:SetAlpha(shouldDesaturate and 0.82 or 1)
end

local function ApplyCooldownCountFont(button, iconSize)
	if not button or not button.Cooldown or type(button.Cooldown.SetCountdownFont) ~= "function" then
		return
	end

	if (iconSize or 0) >= 40 then
		button.Cooldown:SetCountdownFont(LARGE_COOLDOWN_FONT)
	else
		button.Cooldown:SetCountdownFont(SMALL_COOLDOWN_FONT)
	end
end

local function GetEntryVisual(entry)
	local catalogEntry = addon.Catalog:GetEntry(entry.id)
	if not catalogEntry then
		return nil
	end
	local info = {
		name = catalogEntry.name,
		icon = catalogEntry.icon or constants.FALLBACK_ITEM_ICON,
		isAvailable = catalogEntry.isAvailable ~= false,
		isUsable = true,
		kind = catalogEntry.kind,
	}

	if entry.kind == "trinketSlot" then
		info.itemID = catalogEntry.itemID
		info.slotID = catalogEntry.slotID
		info.hasUseEffect = catalogEntry.hasUseEffect == true
		info.isAvailable = catalogEntry.itemID ~= nil
		info.isUsable = readiness and readiness:IsItemReadyForUse(info.itemID, info.slotID) or false
	elseif entry.kind == "item" then
		info.itemID = catalogEntry.itemID
		info.isUsable = readiness and readiness:IsItemReadyForUse(info.itemID, nil) or false
	elseif entry.kind == "spell" or entry.kind == "racial" then
		info.spellID = catalogEntry.spellID
		info.isAvailable = util.IsKnownPlayerSpell(catalogEntry.spellID)
		info.isUsable = info.isAvailable
	end

	return info
end

local function ShouldShowEntryOnBar(entry, visual)
	if not visual then
		return false
	end

	if entry.kind == "trinketSlot" then
		return visual.itemID ~= nil and visual.hasUseEffect == true
	end

	return true
end

local function ApplySpellCooldown(button, spellID)
	local durationObject = util.GetSpellCooldownDurationObject(spellID)
	local chargeObject = util.GetSpellChargeDurationObject(spellID)
	local chargeInfo = spellDisplayState and spellDisplayState:GetChargeInfo(spellID) or nil
	local cooldownState = util.GetSpellCooldownState(spellID)
	local hasMultipleCharges = chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1

	button.cooldownFrameCountsForDesaturation = true
	button.CountText:SetText("")
	if hasMultipleCharges and chargeInfo.currentCharges ~= nil then
		button.CountText:SetText(tostring(chargeInfo.currentCharges))
	end

	-- Some spells report charge duration objects even when they effectively behave like
	-- a normal cooldown with maxCharges == 1. In that case the regular cooldown duration
	-- object produces the correct swipe behavior.
	if hasMultipleCharges and chargeObject and button.Cooldown.SetCooldownFromDurationObject then
		button.Cooldown:SetDrawSwipe(true)
		button.Cooldown:SetCooldownFromDurationObject(chargeObject)
		button.Cooldown:Show()
		return
	end

	-- Pure global-cooldown visuals should swipe without graying the icon. Off-GCD spells
	-- continue to avoid GCD swipe because their spell cooldown state does not report as GCD.
	if cooldownState and cooldownState.isOnGCD and durationObject and button.Cooldown.SetCooldownFromDurationObject then
		button.cooldownFrameCountsForDesaturation = false
		button.Cooldown:SetDrawSwipe(true)
		button.Cooldown:SetCooldownFromDurationObject(durationObject)
		button.Cooldown:Show()
		return
	end

	-- Duration objects are the combat-safe source of truth for custom spell cooldowns.
	-- Some spells can still report GCD-like cooldown state while exposing a valid duration object.
	if durationObject and button.Cooldown.SetCooldownFromDurationObject then
		button.Cooldown:SetDrawSwipe(true)
		button.Cooldown:SetCooldownFromDurationObject(durationObject)
		button.Cooldown:Show()
		return
	end

	ResetCooldown(button)
end

local function ApplyItemCooldown(button, itemID, slotID)
	button.CountText:SetText("")

	local startTime, duration, enabled
	if slotID then
		startTime, duration, enabled = GetInventoryItemCooldown("player", slotID)
	elseif itemID then
		startTime, duration, enabled = C_Item.GetItemCooldownByID and C_Item.GetItemCooldownByID(itemID)
	end

	startTime = util.NumberOrNil(startTime) or 0
	duration = util.NumberOrNil(duration) or 0
	enabled = enabled ~= false and enabled ~= 0

	if enabled and duration > 0 and startTime > 0 then
		button.Cooldown:SetDrawSwipe(true)
		button.Cooldown:SetCooldown(startTime, duration)
		button.Cooldown:Show()
		return
	end

	ResetCooldown(button)
end

function Bars:CreateButton(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(40, 40)

	button.Icon = button:CreateTexture(nil, "BACKGROUND")
	button.Icon:SetAllPoints()

	button.Mask = button:CreateMaskTexture(nil, "ARTWORK")
	button.Mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
	button.Mask:SetAllPoints()
	button.Icon:AddMaskTexture(button.Mask)

	button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.Cooldown:SetAllPoints()
	button.Cooldown:SetDrawBling(false)
	button.Cooldown:SetHideCountdownNumbers(false)
	if button.Cooldown.SetSwipeTexture then
		button.Cooldown:SetSwipeTexture("Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
	end
	if button.Cooldown.SetDrawEdge then
		button.Cooldown:SetDrawEdge(false)
	end
	if button.Cooldown.HookScript then
		button.Cooldown:HookScript("OnShow", function()
			UpdateButtonDesaturation(button)
		end)
		button.Cooldown:HookScript("OnHide", function()
			UpdateButtonDesaturation(button)
		end)
		button.Cooldown:HookScript("OnCooldownDone", function()
			UpdateButtonDesaturation(button)
		end)
	end

	button.Overlay = button:CreateTexture(nil, "OVERLAY")
	button.Overlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")

	button.CountText = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.CountText:SetPoint("BOTTOMRIGHT", -2, 2)
	button.CountText:SetJustifyH("RIGHT")
	button.CountText:SetTextColor(1, 1, 1)
	button.CountText:SetShadowOffset(1, -1)

	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnMouseDown", function(self, buttonName)
		if buttonName ~= "LeftButton" then
			return
		end
		local parent = self:GetParent()
		if parent and editMode and editMode:IsActive() then
			editMode:SelectBarFrame(parent)
		end
	end)
	button:SetScript("OnEnter", function(self)
		if not addon.Profile:ShowTooltips() then
			return
		end
		if not self.entry then
			return
		end
		if GameTooltip_SetDefaultAnchor then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
		else
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		end
		if self.entry.kind == "trinketSlot" and self.entry.slotID then
			GameTooltip:SetInventoryItem("player", self.entry.slotID)
		elseif self.entry.kind == "item" and self.entry.itemID then
			GameTooltip:SetItemByID(self.entry.itemID)
		elseif self.entry.spellID then
			GameTooltip:SetSpellByID(self.entry.spellID)
		end
		if GameTooltip_HideShoppingTooltips then
			GameTooltip_HideShoppingTooltips(GameTooltip)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:SetScript("OnUpdate", function(self)
		if not self:IsShown() or not self.entry then
			return
		end
		if self.entry.kind ~= "spell" and self.entry.kind ~= "racial" then
			return
		end
		UpdateButtonDesaturation(self)
	end)
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(self)
		if not self:GetParent() or not CanDragBarFrame(self:GetParent().barID) then
			return
		end
		if editMode and editMode:IsActive() then
			editMode:SelectBarFrame(self:GetParent())
			if self:GetParent().ClearFrameSnap then
				self:GetParent():ClearFrameSnap()
			end
			if EditModeManagerFrame and EditModeManagerFrame.SetSnapPreviewFrame then
				EditModeManagerFrame:SetSnapPreviewFrame(self:GetParent())
			end
		end
		if self:GetParent() and self:GetParent():IsMovable() then
			addon.isDraggingBar[self:GetParent().barID] = true
			self:GetParent().isDragging = true
			self:GetParent():StartMoving()
		end
	end)
	button:SetScript("OnDragStop", function(self)
		if self:GetParent() then
			self:GetParent():StopMovingOrSizing()
			local parent = self:GetParent()
			parent.isDragging = false
			if editMode and editMode:IsActive() then
				if EditModeManagerFrame and EditModeManagerFrame.ClearSnapPreviewFrame then
					EditModeManagerFrame:ClearSnapPreviewFrame()
				end
				if EditModeMagnetismManager then
					pcall(EditModeMagnetismManager.ApplyMagnetism, EditModeMagnetismManager, parent)
				end
				editMode:ApplyKnownTargetAlignment(parent)
			end
			addon.isDraggingBar[parent.barID] = nil
			PersistDraggedBarPlacement(parent.barID, parent)
		end
	end)

	return button
end

function Bars:AcquireButton(barFrame, index)
	barFrame.buttons = barFrame.buttons or {}
	if not barFrame.buttons[index] then
		barFrame.buttons[index] = self:CreateButton(barFrame)
	end
	return barFrame.buttons[index]
end

function Bars:CreateBarFrame(bar)
	local frame = CreateFrame("Frame", "BuckleUpSidecarBar_" .. bar.id, UIParent, "BackdropTemplate")
	frame.barID = bar.id
	frame.isSidecarBarFrame = true
	frame.buttons = {}
	frame:SetClampedToScreen(true)
	frame:SetMovable(false)
	frame:EnableMouse(false)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not CanDragBarFrame(self.barID) then
			return
		end
		if editMode and editMode:IsActive() then
			editMode:SelectBarFrame(self)
			if self.ClearFrameSnap then
				self:ClearFrameSnap()
			end
			if EditModeManagerFrame and EditModeManagerFrame.SetSnapPreviewFrame then
				EditModeManagerFrame:SetSnapPreviewFrame(self)
			end
		end
		addon.isDraggingBar[self.barID] = true
		self.isDragging = true
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self.isDragging = false
		if editMode and editMode:IsActive() then
			if EditModeManagerFrame and EditModeManagerFrame.ClearSnapPreviewFrame then
				EditModeManagerFrame:ClearSnapPreviewFrame()
			end
			if EditModeMagnetismManager then
				pcall(EditModeMagnetismManager.ApplyMagnetism, EditModeMagnetismManager, self)
			end
			editMode:ApplyKnownTargetAlignment(self)
		end
		addon.isDraggingBar[self.barID] = nil
		PersistDraggedBarPlacement(self.barID, self)
	end)
	frame:SetScript("OnMouseDown", function(self)
		if editMode and editMode:IsActive() then
			editMode:SelectBarFrame(self)
		end
	end)

	CreateBackdrop(frame)
	return frame
end

function Bars:EnsureBarFrames()
	addon.barFrames = addon.barFrames or {}
	local active = {}
	for _, bar in ipairs(addon.Profile:GetBars()) do
		local frame = addon.barFrames[bar.id]
		if not frame then
			frame = self:CreateBarFrame(bar)
			addon.barFrames[bar.id] = frame
		end
		if editMode then
			editMode:AttachBarFrame(frame)
		end
		active[bar.id] = true
		if not addon.isDraggingBar[bar.id] then
			ApplyStoredBarPlacement(frame, bar)
		end
		frame:SetMovable(CanDragBarFrame(bar.id))
		frame:EnableMouse(editMode and editMode:IsActive())
		frame:Show()
		if editMode then
			editMode:RefreshBarFrame(frame)
		end
	end

	for barID, frame in pairs(addon.barFrames) do
		if not active[barID] then
			frame:Hide()
		end
	end
end

function Bars:LayoutBar(barFrame, bar, entries)
	local presentation = barPresentation:Resolve(bar)
	local iconSize = presentation and presentation.iconSize or constants.ESSENTIAL_BASE_ICON_SIZE
	local spacing = presentation and presentation.interIconSpacing or ((constants.DEFAULT_BAR_PADDING or 0) + (constants.BLIZZARD_COOLDOWN_VIEWER_PADDING_OFFSET or 0))
	local barPadding = presentation and presentation.outerPadding or 0
	local growthDirection = bar.growthDirection or constants.GROWTH_RIGHT
	local contentWidth = #entries > 0 and ((#entries * iconSize) + ((#entries - 1) * spacing)) or iconSize
	local width = contentWidth + (barPadding * 2)
	local height = iconSize + (barPadding * 2)

	for index, entry in ipairs(entries) do
		local button = self:AcquireButton(barFrame, index)
		button:ClearAllPoints()
		local offsetX
		if growthDirection == constants.GROWTH_LEFT then
			offsetX = barPadding + ((#entries - index) * (iconSize + spacing))
		elseif growthDirection == constants.GROWTH_CENTER then
			local startX = math.floor((width - contentWidth) / 2)
			offsetX = startX + ((index - 1) * (iconSize + spacing))
		else
			offsetX = barPadding + ((index - 1) * (iconSize + spacing))
		end
		button:SetPoint("TOPLEFT", barFrame, "TOPLEFT", offsetX, -barPadding)
		button:SetSize(iconSize, iconSize)
		ApplyCooldownCountFont(button, iconSize)
		button.Overlay:ClearAllPoints()
		local overlayInset = math.max(5, math.floor(iconSize * 0.18))
		button.Overlay:SetPoint("TOPLEFT", -overlayInset, overlayInset)
		button.Overlay:SetPoint("BOTTOMRIGHT", overlayInset, -overlayInset)
		button.entry = entry
		button:Show()

		local visual = GetEntryVisual(entry)
		if visual and visual.isAvailable then
			button.Icon:SetTexture(visual.icon or constants.FALLBACK_ITEM_ICON)
			button:SetAlpha(1)
			button.baseShouldDesaturate = entry.kind ~= "spell" and entry.kind ~= "racial" and visual.isUsable == false or false
			button.cooldownFrameCountsForDesaturation = true
			button.lastShouldDesaturate = nil
			if entry.kind == "trinketSlot" then
				ApplyItemCooldown(button, visual.itemID, visual.slotID)
			elseif entry.kind == "item" then
				ApplyItemCooldown(button, visual.itemID, nil)
			else
				ApplySpellCooldown(button, visual.spellID)
			end
			UpdateButtonDesaturation(button)
			if skin then
				skin:ApplyToRuntimeButton(button, entry, visual)
			end
		else
			button.Icon:SetTexture((visual and visual.icon) or constants.FALLBACK_ITEM_ICON)
			button:SetAlpha(1)
			button.baseShouldDesaturate = true
			button.cooldownFrameCountsForDesaturation = true
			button.lastShouldDesaturate = nil
			button.CountText:SetText("")
			ResetCooldown(button)
			UpdateButtonDesaturation(button)
			if skin then
				skin:ApplyToRuntimeButton(button, entry, visual)
			end
		end
	end

	for index = #entries + 1, #barFrame.buttons do
		barFrame.buttons[index]:Hide()
	end

	barFrame:SetSize(math.max(width, 18), height)
	ApplyBarPresentation(barFrame, bar, entries)
end

function Bars:RefreshRuntime()
	if not addon.profile then
		return
	end
	self:EnsureBarFrames()

	for _, bar in ipairs(addon.Profile:GetBars()) do
		local frame = addon.barFrames[bar.id]
		local visibleEntries = {}
		for _, entry in ipairs(addon.Profile:GetEntriesForContainer(bar.id)) do
			if entry.enabled ~= false then
				local visual = GetEntryVisual(entry)
				if ShouldShowEntryOnBar(entry, visual) then
				visibleEntries[#visibleEntries + 1] = entry
				end
			end
		end
		self:LayoutBar(frame, bar, visibleEntries)
		if editMode then
			editMode:ReapplyBarAnchor(frame, bar.id)
		end
	end

	if addon.EditModePanel then
		addon.EditModePanel:Refresh()
	end
end
