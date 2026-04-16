local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar

local SettingsIntegration = addon.SettingsIntegration or {}
addon.SettingsIntegration = SettingsIntegration

-- This module only coordinates BuckleUpSidecar with Blizzard's cooldown settings.
-- The embedded organizer itself lives in UI/SidecarOrganizer.lua so the tab hookup
-- and the drag/drop organizer can evolve independently.

local SIDECAR_TAB_TEXTURE = "Interface\\AddOns\\BuckleUpSidecar\\Media\\buckle-up"

local function ResizeSidecarTabIcon(tab)
	if not tab or not tab.Icon then
		return
	end

	tab.Icon:SetSize(18, 18)
	tab.Icon:ClearAllPoints()
	tab.Icon:SetPoint("CENTER", -1, 0)
end

local function ApplySidecarTabTexture(tab, checked)
	if not tab or not tab.Icon then
		return
	end

	tab.Icon:SetAtlas(nil)
	tab.Icon:SetTexture(SIDECAR_TAB_TEXTURE)
	tab.Icon:SetTexCoord(0, 1, 0, 1)
	if checked then
		tab.Icon:SetVertexColor(1, 1, 1, 1)
	else
		tab.Icon:SetVertexColor(0.82, 0.82, 0.82, 1)
	end
	ResizeSidecarTabIcon(tab)
end

function SettingsIntegration:GetSettingsFrame()
	return _G.CooldownViewerSettings
end

function SettingsIntegration:IsReady()
	local frame = self:GetSettingsFrame()
	return frame ~= nil and frame.Inset ~= nil
end

function SettingsIntegration:HideNativeContent()
	local settings = self:GetSettingsFrame()
	settings.SearchBox:Hide()
	settings.SettingsDropdown:Hide()
	settings.CooldownScroll:Hide()
	settings.LayoutDropdown:Hide()
	settings.UndoButton:Hide()
end

function SettingsIntegration:ShowNativeContent()
	local settings = self:GetSettingsFrame()
	settings.SearchBox:Show()
	settings.SettingsDropdown:Show()
	settings.CooldownScroll:Show()
	settings.LayoutDropdown:Show()
	settings.UndoButton:Show()
	self.layoutDropdownOwner = "native"
	if settings.SetupLayoutManagerDropdown then
		settings:SetupLayoutManagerDropdown()
	end
end

function SettingsIntegration:GetSidecarLayoutDropdownSignature()
	local currentSpecKey = addon.profileKey or addon.Util.GetCurrentSpecKey()
	local currentCharacterKey = addon.Profile:GetCurrentCharacterKey()
	local snapshots = addon.Profile:GetLayoutSnapshots()
	local parts = { tostring(currentCharacterKey), tostring(currentSpecKey) }
	for _, snapshot in ipairs(snapshots) do
		parts[#parts + 1] = string.format("%s|%s|%s|%s|%d", tostring(snapshot.key), tostring(snapshot.label), tostring(snapshot.characterKey), tostring(snapshot.specKey), #(snapshot.bars or {}))
	end
	return table.concat(parts, "||")
end

function SettingsIntegration:SetupSidecarLayoutDropdown()
	local settings = self:GetSettingsFrame()
	local dropdown = settings and settings.LayoutDropdown
	if not dropdown then
		return
	end

	dropdown:SetWidth(220)
	if dropdown.SetDefaultText then
		dropdown:SetDefaultText(addon.Util.GetCurrentSpecDisplayLabel())
	end
	if dropdown.SetEnabled then
		dropdown:SetEnabled(true)
	end

	local signature = self:GetSidecarLayoutDropdownSignature()
	if dropdown.SetupMenu and (self.layoutDropdownOwner ~= "sidecar" or self.layoutDropdownMenuSignature ~= signature) then
		self.layoutDropdownOwner = "sidecar"
		self.layoutDropdownMenuSignature = signature
		dropdown:SetupMenu(function(_owner, rootDescription)
			local snapshots = addon.Profile:GetLayoutSnapshots()
			local currentSpecKey = addon.profileKey or addon.Util.GetCurrentSpecKey()
			local currentCharacterKey = addon.Profile:GetCurrentCharacterKey()
			local filteredSnapshots = {}
			for _, snapshot in ipairs(snapshots) do
				if not (
					tostring(snapshot.specKey) == tostring(currentSpecKey)
					and tostring(snapshot.characterKey) == tostring(currentCharacterKey)
				) then
					filteredSnapshots[#filteredSnapshots + 1] = snapshot
				end
			end

			rootDescription:CreateTitle(addon.Util.GetCurrentSpecDisplayLabel())
			rootDescription:CreateDivider()
			rootDescription:CreateTitle("Copy Layout From")
			if #filteredSnapshots == 0 then
				local emptyButton = rootDescription:CreateButton("No other saved layouts", function() end)
				emptyButton:SetEnabled(false)
			else
				for _, snapshot in ipairs(filteredSnapshots) do
					rootDescription:CreateButton(snapshot.label, function()
						local ok = addon.Profile:ApplyLayoutSnapshot(snapshot.key)
						if ok then
							addon.Bars:RefreshRuntime()
							SettingsIntegration:RefreshPanel()
						end
					end)
				end
			end
			rootDescription:CreateDivider()
			rootDescription:CreateButton("Reset Current Layout", function()
				StaticPopupDialogs["BUCKLEUPSIDECAR_RESET_LAYOUT"] = StaticPopupDialogs["BUCKLEUPSIDECAR_RESET_LAYOUT"] or {
					text = "Reset the current sidecar layout to one default bar?",
					button1 = YES,
					button2 = NO,
					OnAccept = function()
						addon.profile.bars = { addon.Util.DeepCopy(addon.Defaults.profile.bars[1]) }
						for _, entry in ipairs(addon.Profile:GetConfiguredEntries()) do
							if entry.containerID ~= addon.Constants.HIDDEN_CONTAINER_ID then
								entry.containerID = addon.Constants.HIDDEN_CONTAINER_ID
							end
						end
						addon.Profile:NormalizeOrders()
						addon.Profile:CommitProfile()
						addon.Profile:RecordLayoutSnapshot()
						addon.Bars:RefreshRuntime()
						SettingsIntegration:RefreshPanel()
					end,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
				StaticPopup_Show("BUCKLEUPSIDECAR_RESET_LAYOUT")
			end)
		end)
	end

	dropdown:Show()
end

function SettingsIntegration:SetSidecarTabChecked(checked)
	if self.sidecarTab then
		self.sidecarTab:SetChecked(checked)
	end
end

function SettingsIntegration:IsSidecarPanelActive()
	return self.panel and self.panel:IsShown() or false
end

function SettingsIntegration:RefreshSidecarTabVisual()
	if self.sidecarTab then
		local isActive = self:IsSidecarPanelActive()
		ApplySidecarTabTexture(self.sidecarTab, isActive)
		if self.sidecarTab.SelectedTexture then
			self.sidecarTab.SelectedTexture:SetShown(isActive)
		end
	end
end

function SettingsIntegration:ClearStaleSidecarTabCheck()
	if self.sidecarTab and not (self.panel and self.panel:IsShown()) and self.sidecarTab:GetChecked() then
		self.sidecarTab:SetChecked(false)
	end
	self:RefreshSidecarTabVisual()
end

function SettingsIntegration:HideSidecarPanel()
	if self.panel then
		self.panel:Hide()
	end
	self:SetSidecarTabChecked(false)
	self:RefreshSidecarTabVisual()
end

function SettingsIntegration:ShowSidecarPanel()
	if not self:IsReady() then
		return
	end

	local settings = self:GetSettingsFrame()
	for _, tab in ipairs(settings.TabButtons or {}) do
		tab:SetChecked(false)
	end

	self:SetSidecarTabChecked(true)
	self:HideNativeContent()
	self:SetupSidecarLayoutDropdown()
	self.panel:Show()
	self:RefreshSidecarTabVisual()
	self:RefreshPanel()

	-- Blizzard's settings panel can reinitialize the shared footer controls during the same
	-- show cycle. Reassert Sidecar ownership on the next frame so /bus config opens reliably.
	C_Timer.After(0, function()
		if self.panel and self.panel:IsShown() then
			self:HideNativeContent()
			self:SetupSidecarLayoutDropdown()
			self:RefreshPanel()
		end
	end)
end

function SettingsIntegration:CreatePanel()
	local settings = self:GetSettingsFrame()
	local panel = CreateFrame("Frame", nil, settings.Inset, "BackdropTemplate")
	panel:SetPoint("TOPLEFT", settings.Inset, "TOPLEFT", 4, -4)
	panel:SetPoint("BOTTOMRIGHT", settings.Inset, "BOTTOMRIGHT", -4, 4)
	panel:Hide()
	self.panel = panel

	self:BuildOrganizerPanel(panel)
end

function SettingsIntegration:CreateSidecarTab()
	local settings = self:GetSettingsFrame()
	local tab = CreateFrame("CheckButton", nil, settings, "LargeSideTabButtonTemplate")
	tab:SetPoint("TOP", settings.AurasTab, "BOTTOM", 0, -3)
	tab.tooltipText = "BuckleUp Sidecar"

	local originalSetChecked = tab.SetChecked
	tab.SetChecked = function(selfButton, checked)
		originalSetChecked(selfButton, checked)
		ApplySidecarTabTexture(selfButton, checked)
	end

	ApplySidecarTabTexture(tab, false)
	tab:HookScript("OnShow", function(selfButton)
		SettingsIntegration:ClearStaleSidecarTabCheck()
		SettingsIntegration:RefreshSidecarTabVisual()
	end)
	tab:HookScript("OnMouseDown", function(selfButton)
		SettingsIntegration:RefreshSidecarTabVisual()
	end)
	tab:HookScript("OnMouseUp", function(selfButton)
		SettingsIntegration:RefreshSidecarTabVisual()
	end)
	tab:SetScript("OnEnter", function(selfButton)
		GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, "Sidecar")
		GameTooltip_AddNormalLine(GameTooltip, "Supplemental trinkets, racials, items, and custom spells.")
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
		if button == "LeftButton" and upInside then
			self:ShowSidecarPanel()
		end
	end)
	self.sidecarTab = tab
end

function SettingsIntegration:HookNativeTabs()
	local settings = self:GetSettingsFrame()
	for _, tab in ipairs(settings.TabButtons or {}) do
		if tab ~= self.sidecarTab and not tab.BuckleUpSidecarHooked then
			tab.BuckleUpSidecarHooked = true
			tab:HookScript("OnMouseUp", function(_, button)
				if button == "LeftButton" and self.panel and self.panel:IsShown() then
					self:HideSidecarPanel()
					self:ShowNativeContent()
				end
			end)
		end
	end
end

function SettingsIntegration:EnsureUI()
	if not self:IsReady() then
		return false
	end
	if not self.sidecarTab then
		self:CreateSidecarTab()
	end
	if not self.panel then
		self:CreatePanel()
	end
	self:HookNativeTabs()
	return true
end

function SettingsIntegration:Initialize()
	if self.initialized then
		return
	end
	if not self:EnsureUI() then
		return
	end
	self.initialized = true

	hooksecurefunc(CooldownViewerSettingsMixin, "SetDisplayMode", function(settingsFrame, _displayMode)
		if self.panel and self.panel:IsShown() then
			self:HideSidecarPanel()
			self:ShowNativeContent()
		end
		if settingsFrame == self:GetSettingsFrame() then
			self:ClearStaleSidecarTabCheck()
		end
	end)

	EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", function()
		self:EnsureUI()
		self:ClearStaleSidecarTabCheck()
		C_Timer.After(0, function()
			self:ClearStaleSidecarTabCheck()
		end)
		self:RefreshPanel()
	end)
end
