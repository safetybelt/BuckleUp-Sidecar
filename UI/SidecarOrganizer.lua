local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar

local SettingsIntegration = addon.SettingsIntegration or {}
addon.SettingsIntegration = SettingsIntegration

local TILE_SIZE = 38
local TILE_GAP = 8
local LANE_PADDING = 10
local MIN_LANE_HEIGHT = 78
local modifiedItemHookInstalled = false
local anchorTargetCycle = {
	addon.Constants.ANCHOR_TARGET_SCREEN,
	addon.Constants.ANCHOR_TARGET_ESSENTIAL,
	addon.Constants.ANCHOR_TARGET_UTILITY,
}
local anchorTargetLabel = {
	[addon.Constants.ANCHOR_TARGET_SCREEN] = "Screen",
	[addon.Constants.ANCHOR_TARGET_ESSENTIAL] = "Essential",
	[addon.Constants.ANCHOR_TARGET_UTILITY] = "Utility",
}
local anchorSideCycle = {
	addon.Constants.ANCHOR_SIDE_LEFT,
	addon.Constants.ANCHOR_SIDE_RIGHT,
	addon.Constants.ANCHOR_SIDE_TOP,
	addon.Constants.ANCHOR_SIDE_BOTTOM,
}
local anchorSideLabel = {
	[addon.Constants.ANCHOR_SIDE_LEFT] = "Left",
	[addon.Constants.ANCHOR_SIDE_RIGHT] = "Right",
	[addon.Constants.ANCHOR_SIDE_TOP] = "Top",
	[addon.Constants.ANCHOR_SIDE_BOTTOM] = "Bottom",
}
local growthDirectionCycle = {
	addon.Constants.GROWTH_LEFT,
	addon.Constants.GROWTH_CENTER,
	addon.Constants.GROWTH_RIGHT,
}
local growthDirectionLabel = {
	[addon.Constants.GROWTH_LEFT] = "Left",
	[addon.Constants.GROWTH_CENTER] = "Center",
	[addon.Constants.GROWTH_RIGHT] = "Right",
}

local function GetNextCycleValue(cycle, currentValue)
	for index, value in ipairs(cycle) do
		if value == currentValue then
			return cycle[(index % #cycle) + 1]
		end
	end
	return cycle[1]
end

local function EnsureEntry(entryID)
	local catalogEntry = addon.Catalog:GetEntry(entryID)
	if not catalogEntry then
		return addon.Profile:GetEntryByID(entryID)
	end
	return addon.Profile:EnsureEntry({
		id = catalogEntry.id,
		kind = catalogEntry.kind,
		spellID = catalogEntry.spellID,
		itemID = catalogEntry.itemID,
		slotID = catalogEntry.slotID,
		containerID = addon.Constants.HIDDEN_CONTAINER_ID,
	})
end

local function GetCursorPoint(frame)
	local x, y = GetCursorPosition()
	local scale = frame:GetEffectiveScale()
	return x / scale, y / scale
end

local function IsCursorOverFrame(frame)
	if not frame or not frame:IsShown() then
		return false
	end
	local cursorX, cursorY = GetCursorPoint(frame)
	local left, right = frame:GetLeft(), frame:GetRight()
	local bottom, top = frame:GetBottom(), frame:GetTop()
	return left and right and bottom and top and cursorX >= left and cursorX <= right and cursorY >= bottom and cursorY <= top
end

local function SetTileTooltip(tile, entry)
	tile:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(entry.name or entry.id, 1, 0.82, 0)
		if entry.kind == "trinketSlot" and entry.slotID then
			GameTooltip:SetInventoryItem("player", entry.slotID)
		elseif entry.kind == "item" and entry.itemID then
			GameTooltip:SetItemByID(entry.itemID)
		elseif entry.spellID then
			GameTooltip:SetSpellByID(entry.spellID)
		end
		GameTooltip:Show()
	end)
	tile:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

local function EntryMatchesSearch(panel, entry)
	local query = panel and panel.searchQuery
	if not query or query == "" then
		return true
	end

	local queryLower = string.lower(query)
	local name = entry.name and string.lower(entry.name) or ""
	if string.find(name, queryLower, 1, true) then
		return true
	end

	if entry.spellID and string.find(tostring(entry.spellID), queryLower, 1, true) then
		return true
	end
	if entry.itemID and string.find(tostring(entry.itemID), queryLower, 1, true) then
		return true
	end
	if entry.slotID and string.find("s" .. tostring(entry.slotID), queryLower, 1, true) then
		return true
	end

	return false
end

local function HideIndicator(panel)
	if panel and panel.Indicator then
		panel.Indicator:Hide()
	end
end

local function EnsureDragOverlay(self)
	if self.dragOverlay then
		return self.dragOverlay
	end

	local overlay = CreateFrame("Frame", nil, UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata("TOOLTIP")
	overlay:EnableMouse(true)
	overlay:Hide()
	overlay:SetScript("OnUpdate", function()
		self:UpdateDropTarget()
	end)
	overlay:SetScript("OnEvent", function(_, event, button)
		if event == "GLOBAL_MOUSE_UP" and button == "LeftButton" then
			self:FinishDrag()
		end
	end)
	self.dragOverlay = overlay
	return overlay
end

local function GetShownTiles(lane)
	local shownTiles = {}
	for _, tile in ipairs(lane.tiles) do
		if tile:IsShown() then
			shownTiles[#shownTiles + 1] = tile
		end
	end
	return shownTiles
end

local function GetLaneDropIndex(lane, cursorX, cursorY)
	local shownTiles = GetShownTiles(lane)
	if #shownTiles == 0 then
		return 1, shownTiles
	end

	local rows = {}
	for index, tile in ipairs(shownTiles) do
		local top, bottom = tile:GetTop(), tile:GetBottom()
		if top and bottom then
			local matchedRow
			for _, row in ipairs(rows) do
				if math.abs(row.top - top) < 2 then
					matchedRow = row
					break
				end
			end
			if not matchedRow then
				matchedRow = {
					top = top,
					bottom = bottom,
					firstIndex = index,
					lastIndex = index,
					tiles = {},
				}
				rows[#rows + 1] = matchedRow
			end
			matchedRow.bottom = bottom
			matchedRow.lastIndex = index
			matchedRow.tiles[#matchedRow.tiles + 1] = tile
		end
	end

	table.sort(rows, function(left, right)
		return left.top > right.top
	end)

	local targetRow = rows[#rows]
	for _, row in ipairs(rows) do
		if cursorY <= row.top and cursorY >= row.bottom then
			targetRow = row
			break
		end
		if cursorY > row.top then
			targetRow = row
			break
		end
	end

	local absoluteIndex = targetRow.lastIndex + 1
	for tileOffset, tile in ipairs(targetRow.tiles) do
		local left, right = tile:GetLeft(), tile:GetRight()
		if left and right then
			local midpoint = (left + right) / 2
			if cursorX < midpoint then
				absoluteIndex = targetRow.firstIndex + tileOffset - 1
				break
			end
		end
	end

	return absoluteIndex, shownTiles
end

local function UpdateLaneActionVisibility(lane)
	if not lane or not lane.showActions then
		return
	end

	local isHovering = MouseIsOver(lane.Header) or MouseIsOver(lane.RenameButton) or MouseIsOver(lane.DeleteButton) or MouseIsOver(lane.LayoutButton)
	if isHovering then
		lane.RenameButton:Show()
		lane.DeleteButton:Show()
		lane.LayoutButton:Show()
	else
		lane.RenameButton:Hide()
		lane.DeleteButton:Hide()
		lane.LayoutButton:Hide()
	end
end

local function OpenAddEntryDialog(kind)
	if not modifiedItemHookInstalled and type(hooksecurefunc) == "function" then
		modifiedItemHookInstalled = true
		hooksecurefunc("HandleModifiedItemClick", function(link)
			if not IsModifiedClick("CHATLINK") or not link then
				return
			end

			for _, dialogKey in ipairs({ "BUCKLEUPSIDECAR_ADD_ITEM", "BUCKLEUPSIDECAR_ADD_SPELL" }) do
				local popup = StaticPopup_FindVisible(dialogKey)
				if popup then
					local editBox = popup.editBox or popup.EditBox
					if editBox and editBox:HasFocus() then
						editBox:SetText(link)
						editBox:SetFocus()
						editBox:HighlightText()
						break
					end
				end
			end
		end)
	end

	local dialogKey = kind == "spell" and "BUCKLEUPSIDECAR_ADD_SPELL" or "BUCKLEUPSIDECAR_ADD_ITEM"
	if not StaticPopupDialogs[dialogKey] then
		StaticPopupDialogs[dialogKey] = {
			text = kind == "spell" and "Add spell by ID" or "Add item by ID",
			button1 = ADD,
			button2 = CANCEL,
			hasEditBox = true,
			whileDead = true,
			hideOnEscape = true,
			timeout = 0,
			preferredIndex = 3,
			OnShow = function(self)
				local editBox = self.editBox or self.EditBox
				if editBox then
					if not editBox.BuckleUpSidecarLinkHooks then
						editBox.BuckleUpSidecarLinkHooks = true
						editBox:HookScript("OnEditFocusGained", function(focusedBox)
							focusedBox.BuckleUpPreviousActiveChatEditBox = _G.ACTIVE_CHAT_EDIT_BOX
							focusedBox.BuckleUpPreviousLastActiveChatEditBox = _G.LAST_ACTIVE_CHAT_EDIT_BOX
							_G.ACTIVE_CHAT_EDIT_BOX = focusedBox
							_G.LAST_ACTIVE_CHAT_EDIT_BOX = focusedBox
						end)
						editBox:HookScript("OnEditFocusLost", function(focusedBox)
							if _G.ACTIVE_CHAT_EDIT_BOX == focusedBox then
								_G.ACTIVE_CHAT_EDIT_BOX = focusedBox.BuckleUpPreviousActiveChatEditBox
							end
							if _G.LAST_ACTIVE_CHAT_EDIT_BOX == focusedBox then
								_G.LAST_ACTIVE_CHAT_EDIT_BOX = focusedBox.BuckleUpPreviousLastActiveChatEditBox
							end
						end)
					end
					editBox:SetText("")
					editBox:SetFocus()
					editBox:HighlightText()
				end
			end,
			OnHide = function(self)
				local editBox = self.editBox or self.EditBox
				if editBox then
					if _G.ACTIVE_CHAT_EDIT_BOX == editBox then
						_G.ACTIVE_CHAT_EDIT_BOX = editBox.BuckleUpPreviousActiveChatEditBox
					end
					if _G.LAST_ACTIVE_CHAT_EDIT_BOX == editBox then
						_G.LAST_ACTIVE_CHAT_EDIT_BOX = editBox.BuckleUpPreviousLastActiveChatEditBox
					end
				end
			end,
			OnAccept = function(self)
				local editBox = self.editBox or self.EditBox
				local rawText = (editBox and editBox:GetText()) or ""
				local rawID = tonumber(rawText)
				if not rawID then
					if kind == "item" then
						rawID = tonumber(rawText:match("item:(%d+)"))
					elseif kind == "spell" then
						rawID = tonumber(rawText:match("spell:(%d+)"))
					end
				end
				if not rawID then
					return
				end

				if kind == "spell" then
					if not addon.Util.IsValidSpellID(rawID) then
						if addon.Print then
							addon.Print("That spell ID could not be validated. Try a real spell ID.")
						end
						return
					end
					addon.Profile:EnsureEntry({
						id = addon.Util.MakeEntryID("spell", rawID),
						kind = "spell",
						spellID = rawID,
						containerID = addon.Constants.HIDDEN_CONTAINER_ID,
					})
					addon.Catalog:Rebuild()
					addon.Bars:RefreshRuntime()
					SettingsIntegration:RefreshPanel()
					return
				else
					addon.Util.ValidateItemIDAsync(rawID, function(validItemID)
						addon.Profile:EnsureEntry({
							id = addon.Util.MakeEntryID("item", validItemID),
							kind = "item",
							itemID = validItemID,
							containerID = addon.Constants.HIDDEN_CONTAINER_ID,
						})
						addon.Catalog:Rebuild()
						addon.Bars:RefreshRuntime()
						SettingsIntegration:RefreshPanel()
						if addon.Print then
							addon.Print("Added item:" .. tostring(validItemID))
						end
					end, function()
						if addon.Print then
							addon.Print("That item ID could not be validated. Try a real item ID or shift-click a real item.")
						end
					end)
					return
				end
			end,
			EditBoxOnEnterPressed = function(self)
				local parent = self:GetParent()
				if parent and parent.button1 and parent.button1:IsEnabled() then
					parent.button1:Click()
				end
			end,
		}
	end

	StaticPopup_Show(dialogKey)
end

function SettingsIntegration:GetContainerDefinitions()
	local containers = {}
	for _, bar in ipairs(addon.Profile:GetBars()) do
		containers[#containers + 1] = { id = bar.id, label = bar.name }
	end
	containers[#containers + 1] = { id = addon.Constants.HIDDEN_CONTAINER_ID, label = "Not Displayed" }
	return containers
end

function SettingsIntegration:GetEntriesForContainer(containerID)
	local cache = self.organizerEntriesByContainer
	if not cache then
		return {}
	end
	return cache[containerID] or {}
end

function SettingsIntegration:RebuildOrganizerEntryCache()
	local configuredByID = {}
	for _, configuredEntry in ipairs(addon.Profile:GetConfiguredEntries()) do
		configuredByID[configuredEntry.id] = configuredEntry
	end

	local entriesByContainer = {}
	for _, entry in ipairs(addon.Catalog:GetOrderedEntries()) do
		local configured = configuredByID[entry.id]
		local containerID = (configured and configured.containerID) or addon.Constants.HIDDEN_CONTAINER_ID
		entriesByContainer[containerID] = entriesByContainer[containerID] or {}
		entriesByContainer[containerID][#entriesByContainer[containerID] + 1] = entry
	end

	for containerID, entries in pairs(entriesByContainer) do
		table.sort(entries, function(left, right)
			local leftConfigured = configuredByID[left.id]
			local rightConfigured = configuredByID[right.id]
			local leftOrder = leftConfigured and leftConfigured.order or 9999
			local rightOrder = rightConfigured and rightConfigured.order or 9999
			if leftOrder == rightOrder then
				return (left.name or left.id) < (right.name or right.id)
			end
			return leftOrder < rightOrder
		end)
		entriesByContainer[containerID] = entries
	end

	self.organizerEntriesByContainer = entriesByContainer
end

function SettingsIntegration:CreateTile(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(TILE_SIZE, TILE_SIZE)
	button:RegisterForDrag("LeftButton")

	button.Icon = button:CreateTexture(nil, "BACKGROUND")
	button.Icon:SetAllPoints()
	button.Mask = button:CreateMaskTexture(nil, "ARTWORK")
	button.Mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
	button.Mask:SetAllPoints()
	button.Icon:AddMaskTexture(button.Mask)

	button.Overlay = button:CreateTexture(nil, "OVERLAY")
	button.Overlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")

	button.Shade = button:CreateTexture(nil, "OVERLAY")
	button.Shade:SetAllPoints()
	button.Shade:SetColorTexture(0, 0, 0, 0.45)
	button.Shade:Hide()

	button.IDText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.IDText:SetPoint("BOTTOM", 0, 2)
	button.IDText:SetScale(0.8)
	button.IDText:SetTextColor(0.9, 0.9, 0.9)
	return button
end

function SettingsIntegration:CreateLane(parent)
	local lane = CreateFrame("Frame", nil, parent)
	lane:EnableMouse(true)
	lane.tiles = {}

	lane.Header = CreateFrame("Frame", nil, lane, "BackdropTemplate")
	lane.Header:SetHeight(26)
	lane.Header:SetPoint("TOPLEFT", lane, "TOPLEFT", 2, 0)
	lane.Header:SetPoint("TOPRIGHT", lane, "TOPRIGHT", -2, 0)
	lane.Header:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	lane.Header:SetBackdropColor(0.10, 0.10, 0.10, 0.92)
	lane.Header:SetBackdropBorderColor(0.30, 0.30, 0.30, 0.95)
	lane.Header:SetScript("OnEnter", function()
		UpdateLaneActionVisibility(lane)
	end)
	lane.Header:SetScript("OnLeave", function()
		C_Timer.After(0, function()
			UpdateLaneActionVisibility(lane)
		end)
	end)

	lane.Title = lane.Header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	lane.Title:SetPoint("LEFT", lane.Header, "LEFT", 12, 0)
	lane.Title:SetTextColor(1, 0.82, 0)
	lane.Count = lane.Header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.Count:SetPoint("RIGHT", lane.Header, "RIGHT", -10, 0)
	lane.Count:SetTextColor(0.72, 0.72, 0.72)

	lane.RenameButton = CreateFrame("Button", nil, lane.Header)
	lane.RenameButton:SetSize(44, 16)
	lane.RenameButton.Text = lane.RenameButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.RenameButton.Text:SetAllPoints()
	lane.RenameButton.Text:SetJustifyH("CENTER")
	lane.RenameButton.Text:SetText("Rename")
	lane.RenameButton.Text:SetTextColor(0.72, 0.72, 0.72)
	lane.RenameButton:Hide()
	lane.RenameButton:SetScript("OnEnter", function()
		UpdateLaneActionVisibility(lane)
		lane.RenameButton.Text:SetTextColor(1, 0.82, 0)
	end)
	lane.RenameButton:SetScript("OnLeave", function()
		C_Timer.After(0, function()
			UpdateLaneActionVisibility(lane)
		end)
		lane.RenameButton.Text:SetTextColor(0.72, 0.72, 0.72)
	end)

	lane.DeleteButton = CreateFrame("Button", nil, lane.Header)
	lane.DeleteButton:SetSize(36, 16)
	lane.DeleteButton.Text = lane.DeleteButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.DeleteButton.Text:SetAllPoints()
	lane.DeleteButton.Text:SetJustifyH("CENTER")
	lane.DeleteButton.Text:SetText("Delete")
	lane.DeleteButton.Text:SetTextColor(0.72, 0.72, 0.72)
	lane.DeleteButton:Hide()
	lane.DeleteButton:SetScript("OnEnter", function()
		UpdateLaneActionVisibility(lane)
		lane.DeleteButton.Text:SetTextColor(1, 0.82, 0)
	end)
	lane.DeleteButton:SetScript("OnLeave", function()
		C_Timer.After(0, function()
			UpdateLaneActionVisibility(lane)
		end)
		lane.DeleteButton.Text:SetTextColor(0.72, 0.72, 0.72)
	end)

	lane.LayoutButton = CreateFrame("Button", nil, lane.Header)
	lane.LayoutButton:SetSize(40, 16)
	lane.LayoutButton.Text = lane.LayoutButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutButton.Text:SetAllPoints()
	lane.LayoutButton.Text:SetJustifyH("CENTER")
	lane.LayoutButton.Text:SetText("Layout")
	lane.LayoutButton.Text:SetTextColor(0.72, 0.72, 0.72)
	lane.LayoutButton:Hide()
	lane.LayoutButton:SetScript("OnEnter", function()
		UpdateLaneActionVisibility(lane)
		lane.LayoutButton.Text:SetTextColor(1, 0.82, 0)
	end)
	lane.LayoutButton:SetScript("OnLeave", function()
		C_Timer.After(0, function()
			UpdateLaneActionVisibility(lane)
		end)
		lane.LayoutButton.Text:SetTextColor(0.72, 0.72, 0.72)
	end)

	lane.LayoutEditor = CreateFrame("Frame", nil, lane, "BackdropTemplate")
	lane.LayoutEditor:SetHeight(66)
	lane.LayoutEditor:SetPoint("TOPLEFT", lane.Header, "BOTTOMLEFT", 6, -6)
	lane.LayoutEditor:SetPoint("TOPRIGHT", lane.Header, "BOTTOMRIGHT", -6, -6)
	lane.LayoutEditor:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	lane.LayoutEditor:SetBackdropColor(0.08, 0.08, 0.08, 0.92)
	lane.LayoutEditor:SetBackdropBorderColor(0.26, 0.26, 0.26, 0.92)
	lane.LayoutEditor:Hide()

	lane.LayoutSizeLabel = lane.LayoutEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutSizeLabel:SetPoint("TOPLEFT", lane.LayoutEditor, "TOPLEFT", 14, -14)
	lane.LayoutSizeLabel:SetTextColor(0.82, 0.82, 0.82)
	lane.LayoutSizeLabel:SetText("Size")

	lane.LayoutSizeDown = CreateFrame("Button", nil, lane.LayoutEditor)
	lane.LayoutSizeDown:SetSize(18, 18)
	lane.LayoutSizeDown:SetPoint("LEFT", lane.LayoutSizeLabel, "RIGHT", 10, 0)
	lane.LayoutSizeDown.Text = lane.LayoutSizeDown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutSizeDown.Text:SetAllPoints()
	lane.LayoutSizeDown.Text:SetText("-")

	lane.LayoutSizeValue = lane.LayoutEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutSizeValue:SetPoint("LEFT", lane.LayoutSizeDown, "RIGHT", 8, 0)
	lane.LayoutSizeValue:SetWidth(30)
	lane.LayoutSizeValue:SetJustifyH("CENTER")
	lane.LayoutSizeValue:SetTextColor(1, 0.82, 0)

	lane.LayoutSizeUp = CreateFrame("Button", nil, lane.LayoutEditor)
	lane.LayoutSizeUp:SetSize(18, 18)
	lane.LayoutSizeUp:SetPoint("LEFT", lane.LayoutSizeValue, "RIGHT", 8, 0)
	lane.LayoutSizeUp.Text = lane.LayoutSizeUp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutSizeUp.Text:SetAllPoints()
	lane.LayoutSizeUp.Text:SetText("+")

	lane.LayoutSpacingLabel = lane.LayoutEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutSpacingLabel:SetPoint("TOPLEFT", lane.LayoutEditor, "TOPLEFT", 154, -14)
	lane.LayoutSpacingLabel:SetTextColor(0.82, 0.82, 0.82)
	lane.LayoutSpacingLabel:SetText("Spacing")

	lane.LayoutSpacingDown = CreateFrame("Button", nil, lane.LayoutEditor)
	lane.LayoutSpacingDown:SetSize(18, 18)
	lane.LayoutSpacingDown:SetPoint("LEFT", lane.LayoutSpacingLabel, "RIGHT", 10, 0)
	lane.LayoutSpacingDown.Text = lane.LayoutSpacingDown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutSpacingDown.Text:SetAllPoints()
	lane.LayoutSpacingDown.Text:SetText("-")

	lane.LayoutSpacingValue = lane.LayoutEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutSpacingValue:SetPoint("LEFT", lane.LayoutSpacingDown, "RIGHT", 8, 0)
	lane.LayoutSpacingValue:SetWidth(28)
	lane.LayoutSpacingValue:SetJustifyH("CENTER")
	lane.LayoutSpacingValue:SetTextColor(1, 0.82, 0)

	lane.LayoutSpacingUp = CreateFrame("Button", nil, lane.LayoutEditor)
	lane.LayoutSpacingUp:SetSize(18, 18)
	lane.LayoutSpacingUp:SetPoint("LEFT", lane.LayoutSpacingValue, "RIGHT", 8, 0)
	lane.LayoutSpacingUp.Text = lane.LayoutSpacingUp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutSpacingUp.Text:SetAllPoints()
	lane.LayoutSpacingUp.Text:SetText("+")

	lane.LayoutAnchorLabel = lane.LayoutEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutAnchorLabel:SetPoint("TOPLEFT", lane.LayoutEditor, "TOPLEFT", 14, -38)
	lane.LayoutAnchorLabel:SetTextColor(0.82, 0.82, 0.82)
	lane.LayoutAnchorLabel:SetText("Anchor")

	lane.LayoutAnchorButton = CreateFrame("Button", nil, lane.LayoutEditor)
	lane.LayoutAnchorButton:SetSize(72, 18)
	lane.LayoutAnchorButton:SetPoint("LEFT", lane.LayoutAnchorLabel, "RIGHT", 10, 0)
	lane.LayoutAnchorButton.Text = lane.LayoutAnchorButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutAnchorButton.Text:SetAllPoints()
	lane.LayoutAnchorButton.Text:SetJustifyH("CENTER")

	lane.LayoutSideLabel = lane.LayoutEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutSideLabel:SetPoint("TOPLEFT", lane.LayoutEditor, "TOPLEFT", 154, -38)
	lane.LayoutSideLabel:SetTextColor(0.82, 0.82, 0.82)
	lane.LayoutSideLabel:SetText("Side")

	lane.LayoutSideButton = CreateFrame("Button", nil, lane.LayoutEditor)
	lane.LayoutSideButton:SetSize(58, 18)
	lane.LayoutSideButton:SetPoint("LEFT", lane.LayoutSideLabel, "RIGHT", 10, 0)
	lane.LayoutSideButton.Text = lane.LayoutSideButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutSideButton.Text:SetAllPoints()
	lane.LayoutSideButton.Text:SetJustifyH("CENTER")

	lane.LayoutGrowthLabel = lane.LayoutEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutGrowthLabel:SetPoint("TOPLEFT", lane.LayoutEditor, "TOPLEFT", 258, -38)
	lane.LayoutGrowthLabel:SetTextColor(0.82, 0.82, 0.82)
	lane.LayoutGrowthLabel:SetText("Grow")

	lane.LayoutGrowthButton = CreateFrame("Button", nil, lane.LayoutEditor)
	lane.LayoutGrowthButton:SetSize(52, 18)
	lane.LayoutGrowthButton:SetPoint("LEFT", lane.LayoutGrowthLabel, "RIGHT", 10, 0)
	lane.LayoutGrowthButton.Text = lane.LayoutGrowthButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.LayoutGrowthButton.Text:SetAllPoints()
	lane.LayoutGrowthButton.Text:SetJustifyH("CENTER")

	lane.NameEditor = CreateFrame("EditBox", nil, lane, "InputBoxTemplate")
	lane.NameEditor:SetSize(150, 20)
	lane.NameEditor:SetAutoFocus(false)
	lane.NameEditor:Hide()
	lane.NameEditor:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		self:Hide()
		if self.lane then
			self.lane.Title:Show()
		end
	end)
	lane.NameEditor:SetScript("OnEnterPressed", function(self)
		local text = self:GetText()
		if self.lane and self.lane.containerID and text and text ~= "" then
			addon.Profile:RenameBar(self.lane.containerID, text)
			addon.Bars:RefreshRuntime()
			SettingsIntegration:RefreshPanel()
		end
		self:ClearFocus()
		self:Hide()
		if self.lane then
			self.lane.Title:Show()
		end
	end)

	lane.Indicator = lane:CreateTexture(nil, "OVERLAY")
	lane.Indicator:SetColorTexture(1, 0.82, 0, 0.95)
	lane.Indicator:SetWidth(4)
	lane.Indicator:Hide()
	return lane
end

function SettingsIntegration:LayoutLane(lane, entries)
	local contentWidth = math.max(240, (lane:GetWidth() > 0 and lane:GetWidth() or 320) - 12)
	local columns = math.max(1, math.floor((contentWidth + TILE_GAP) / (TILE_SIZE + TILE_GAP)))
	local tilesTopOffset = lane.layoutExpanded and 110 or 32

	for index, entry in ipairs(entries) do
		local tile = lane.tiles[index]
		if not tile then
			tile = self:CreateTile(lane)
			lane.tiles[index] = tile
		end

		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", 12 + (column * (TILE_SIZE + TILE_GAP)), -tilesTopOffset - (row * (TILE_SIZE + TILE_GAP)))
		local overlayInset = math.max(5, math.floor(TILE_SIZE * 0.18))
		tile.Overlay:ClearAllPoints()
		tile.Overlay:SetPoint("TOPLEFT", -overlayInset, overlayInset)
		tile.Overlay:SetPoint("BOTTOMRIGHT", overlayInset, -overlayInset)

		tile.entry = entry
		local matchesSearch = EntryMatchesSearch(self.panel, entry)
		tile.Icon:SetTexture(entry.icon or addon.Constants.FALLBACK_ITEM_ICON)
		tile.Icon:SetDesaturated(entry.isAvailable == false)
		tile.Shade:SetShown(entry.isAvailable == false)
		tile.IDText:SetText(entry.spellID and tostring(entry.spellID) or (entry.slotID and ("S" .. tostring(entry.slotID)) or ""))
		if self.panel and self.panel.searchQuery and self.panel.searchQuery ~= "" and not matchesSearch then
			tile:SetAlpha(0.28)
		else
			tile:SetAlpha(1)
		end
		SetTileTooltip(tile, entry)
		tile:SetScript("OnDragStart", function()
			self:StartDrag(entry, lane.containerID)
		end)
		tile:SetScript("OnMouseUp", function(_, button)
			if button == "LeftButton" then
				self:FinishDrag()
			end
		end)
		tile:Show()
	end

	for index = #entries + 1, #lane.tiles do
		lane.tiles[index]:Hide()
	end

	local rows = math.max(1, math.floor((#entries - 1) / columns) + 1)
	local layoutExtra = lane.layoutExpanded and 78 or 0
	lane:SetHeight(math.max(MIN_LANE_HEIGHT, 30 + layoutExtra + (rows * TILE_SIZE) + ((rows - 1) * TILE_GAP) + 6))
end

function SettingsIntegration:AdjustBarLayout(barID, field, delta, minValue, maxValue)
	local bar = addon.Profile:GetBarByID(barID)
	if not bar then
		return
	end

	local currentValue = bar[field] or 0
	local nextValue = math.min(maxValue, math.max(minValue, currentValue + delta))
	if nextValue == currentValue then
		return
	end

	addon.Profile:UpdateBarLayout(barID, { [field] = nextValue })
	addon.Bars:RefreshRuntime()
	self:RefreshPanel()
end

function SettingsIntegration:CycleBarLayoutValue(barID, field, cycle)
	local bar = addon.Profile:GetBarByID(barID)
	if not bar then
		return
	end

	local nextValue = GetNextCycleValue(cycle, bar[field])
	local layoutUpdate = { [field] = nextValue }
	if field == "anchorTarget" then
		layoutUpdate.x = 0
		layoutUpdate.y = 0
		if nextValue ~= addon.Constants.ANCHOR_TARGET_SCREEN and (bar.anchorSide == nil or bar.anchorSide == addon.Constants.ANCHOR_SIDE_BOTTOM) then
			layoutUpdate.anchorSide = addon.Constants.ANCHOR_SIDE_RIGHT
		end
	end
	addon.Profile:UpdateBarLayout(barID, layoutUpdate)
	addon.Bars:RefreshRuntime()
	self:RefreshPanel()
end

function SettingsIntegration:ToggleLayoutEditor(barID)
	if self.expandedLayoutBarID == barID then
		self.expandedLayoutBarID = nil
	else
		self.expandedLayoutBarID = barID
	end
	self:RefreshPanel()
end

function SettingsIntegration:RefreshLanes()
	if not self.panel or not self.panel:IsShown() then
		return
	end

	self:RebuildOrganizerEntryCache()

	local contentWidth = math.max(300, (self.panel.Scroll:GetWidth() > 0 and self.panel.Scroll:GetWidth() or 320) - 18)
	self.panel.Content:SetWidth(contentWidth)

	local containers = self:GetContainerDefinitions()
	self.lanes = self.lanes or {}
	local previousLane
	for index, container in ipairs(containers) do
		local lane = self.lanes[index]
		if not lane then
			lane = self:CreateLane(self.panel.Content)
			self.lanes[index] = lane
		end
		lane.containerID = container.id
		lane:ClearAllPoints()
		if previousLane then
			lane:SetPoint("TOPLEFT", previousLane, "BOTTOMLEFT", 0, -LANE_PADDING)
			lane:SetPoint("TOPRIGHT", previousLane, "BOTTOMRIGHT", 0, -LANE_PADDING)
		else
			lane:SetPoint("TOPLEFT", self.panel.Content, "TOPLEFT", 8, 0)
			lane:SetPoint("TOPRIGHT", self.panel.Content, "TOPRIGHT", 8, -2)
		end
		lane:SetWidth(contentWidth - 16)
		lane.Header:SetPoint("TOPLEFT", lane, "TOPLEFT", 0, 0)
		lane.Header:SetPoint("TOPRIGHT", lane, "TOPRIGHT", 0, 0)

		local entries = self:GetEntriesForContainer(container.id)
		lane.Title:SetText(container.label)
		lane.Count:SetText(string.format("%d entries", #entries))
		lane.NameEditor.lane = lane
		lane.layoutExpanded = self.expandedLayoutBarID == container.id
		lane.NameEditor:ClearAllPoints()
		lane.NameEditor:SetPoint("TOPLEFT", lane.Header, "TOPLEFT", 8, -2)
		lane.RenameButton:ClearAllPoints()
		lane.DeleteButton:ClearAllPoints()
		lane.LayoutButton:ClearAllPoints()
		lane.DeleteButton:SetPoint("RIGHT", lane.Header, "RIGHT", -12, 0)
		lane.LayoutButton:SetPoint("RIGHT", lane.DeleteButton, "LEFT", -8, 0)
		lane.RenameButton:SetPoint("RIGHT", lane.LayoutButton, "LEFT", -8, 0)
		lane.Count:ClearAllPoints()
		lane.showActions = container.id ~= addon.Constants.HIDDEN_CONTAINER_ID
		if container.id == addon.Constants.HIDDEN_CONTAINER_ID then
			lane.RenameButton:Hide()
			lane.DeleteButton:Hide()
			lane.LayoutButton:Hide()
			lane.LayoutEditor:Hide()
			lane.NameEditor:Hide()
			lane.Title:Show()
			lane.Count:SetPoint("RIGHT", lane.Header, "RIGHT", -10, 0)
			lane.Count:SetText(string.format("%d entries", #entries))
		else
			lane.RenameButton:Hide()
			lane.DeleteButton:Hide()
			lane.LayoutButton:Hide()
			lane.Count:SetPoint("RIGHT", lane.Header, "RIGHT", -10, 0)
			lane.Count:SetText("")
			lane.RenameButton:SetScript("OnClick", function()
				lane.Title:Hide()
				lane.NameEditor:SetText(container.label)
				lane.NameEditor:Show()
				lane.NameEditor:SetFocus()
				lane.NameEditor:HighlightText()
			end)
			lane.DeleteButton:SetScript("OnClick", function()
				StaticPopupDialogs["BUCKLEUPSIDECAR_DELETE_BAR"] = StaticPopupDialogs["BUCKLEUPSIDECAR_DELETE_BAR"] or {
					text = "Delete this sidecar bar? Assigned entries will move to Not Displayed.",
					button1 = YES,
					button2 = NO,
					OnAccept = function(popup)
						if popup and popup.barID then
							addon.Profile:DeleteBar(popup.barID)
							addon.Catalog:Rebuild()
							addon.Bars:RefreshRuntime()
							SettingsIntegration:RefreshPanel()
						end
					end,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
				local popup = StaticPopup_Show("BUCKLEUPSIDECAR_DELETE_BAR")
				if popup then
					popup.barID = container.id
				end
			end)
			lane.LayoutButton:SetScript("OnClick", function(self)
				SettingsIntegration:ToggleLayoutEditor(container.id)
			end)
			local currentBar = addon.Profile:GetBarByID(container.id)
			if lane.layoutExpanded and currentBar then
				lane.LayoutEditor:Show()
				lane.LayoutSizeValue:SetText(tostring(currentBar.iconSize or 40))
				lane.LayoutSpacingValue:SetText(tostring(currentBar.spacing or 6))
				lane.LayoutAnchorButton.Text:SetText(anchorTargetLabel[currentBar.anchorTarget] or "Screen")
				lane.LayoutSideButton.Text:SetText(anchorSideLabel[currentBar.anchorSide] or "Center")
				lane.LayoutGrowthButton.Text:SetText(growthDirectionLabel[currentBar.growthDirection] or "Right")
				lane.LayoutSizeDown:SetScript("OnClick", function()
					SettingsIntegration:AdjustBarLayout(container.id, "iconSize", -2, 24, 72)
				end)
				lane.LayoutSizeUp:SetScript("OnClick", function()
					SettingsIntegration:AdjustBarLayout(container.id, "iconSize", 2, 24, 72)
				end)
				lane.LayoutSpacingDown:SetScript("OnClick", function()
					SettingsIntegration:AdjustBarLayout(container.id, "spacing", -1, 0, 24)
				end)
				lane.LayoutSpacingUp:SetScript("OnClick", function()
					SettingsIntegration:AdjustBarLayout(container.id, "spacing", 1, 0, 24)
				end)
				lane.LayoutAnchorButton:SetScript("OnClick", function()
					SettingsIntegration:CycleBarLayoutValue(container.id, "anchorTarget", anchorTargetCycle)
				end)
				lane.LayoutSideButton:SetScript("OnClick", function()
					SettingsIntegration:CycleBarLayoutValue(container.id, "anchorSide", anchorSideCycle)
				end)
				lane.LayoutGrowthButton:SetScript("OnClick", function()
					SettingsIntegration:CycleBarLayoutValue(container.id, "growthDirection", growthDirectionCycle)
				end)
			else
				lane.LayoutEditor:Hide()
			end
		end
		self:LayoutLane(lane, entries)
		lane:Show()
		previousLane = lane
	end

	for index = #containers + 1, #self.lanes do
		self.lanes[index]:Hide()
	end

	local totalHeight = 1
	if previousLane then
		totalHeight = math.abs(previousLane:GetTop() - self.panel.Content:GetTop()) + previousLane:GetHeight() + 8
	end
	self.panel.Content:SetHeight(math.max(1, totalHeight))
end

function SettingsIntegration:RefreshPanel()
	if not self.panel then
		return
	end
	if self.panel:IsShown() and self.GetSettingsFrame and self:GetSettingsFrame() then
		self:SetupSidecarLayoutDropdown()
	end
	self:RefreshLanes()
end

function SettingsIntegration:UpdateDropTarget()
	local drag = self.dragState
	if not drag or not drag.proxy then
		return
	end

	local cursorX, cursorY = GetCursorPoint(UIParent)
	drag.proxy:ClearAllPoints()
	drag.proxy:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX + 12, cursorY + 12)
	drag.targetContainerID = nil
	drag.targetIndex = nil

	for _, lane in ipairs(self.lanes or {}) do
		HideIndicator(lane)
		lane.Header:SetBackdropBorderColor(0.30, 0.30, 0.30, 0.95)
		if lane:IsShown() and IsCursorOverFrame(lane) then
			lane.Header:SetBackdropBorderColor(0.95, 0.82, 0.10, 0.95)
			drag.targetContainerID = lane.containerID

			local targetIndex, shownTiles = GetLaneDropIndex(lane, cursorX, cursorY)
			drag.targetIndex = targetIndex

			local nextTile = shownTiles[targetIndex]
			local previousTile = shownTiles[targetIndex - 1]
			lane.Indicator:ClearAllPoints()
			if nextTile and nextTile:IsShown() then
				lane.Indicator:SetPoint("TOPLEFT", nextTile, "TOPLEFT", -4, 2)
				lane.Indicator:SetPoint("BOTTOMLEFT", nextTile, "BOTTOMLEFT", -4, -2)
				lane.Indicator:Show()
			elseif previousTile and previousTile:IsShown() then
				lane.Indicator:SetPoint("TOPRIGHT", previousTile, "TOPRIGHT", 4, 2)
				lane.Indicator:SetPoint("BOTTOMRIGHT", previousTile, "BOTTOMRIGHT", 4, -2)
				lane.Indicator:Show()
			end
		end
	end
end

function SettingsIntegration:StartDrag(entry, sourceContainerID)
	self.dragState = self.dragState or {}
	local drag = self.dragState
	drag.entryID = entry.id
	drag.sourceContainerID = sourceContainerID
	drag.targetContainerID = sourceContainerID
	drag.targetIndex = nil

	if not self.panel.DragProxy then
		local proxy = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		proxy:SetFrameStrata("TOOLTIP")
		proxy:SetSize(220, 24)
		proxy:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		proxy:SetBackdropColor(0.08, 0.08, 0.08, 0.90)
		proxy:SetBackdropBorderColor(0.95, 0.82, 0.10, 0.95)
		proxy.Icon = proxy:CreateTexture(nil, "ARTWORK")
		proxy.Icon:SetPoint("LEFT", 4, 0)
		proxy.Icon:SetSize(18, 18)
		proxy.Text = proxy:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		proxy.Text:SetPoint("LEFT", proxy.Icon, "RIGHT", 6, 0)
		proxy.Text:SetWidth(190)
		proxy.Text:SetJustifyH("LEFT")
		proxy:EnableMouse(false)
		self.panel.DragProxy = proxy
	end

	drag.proxy = self.panel.DragProxy
	drag.proxy.Icon:SetTexture(entry.icon or addon.Constants.FALLBACK_ITEM_ICON)
	drag.proxy.Text:SetText(entry.name or entry.id)
	drag.proxy:Show()
	local overlay = EnsureDragOverlay(self)
	overlay:RegisterEvent("GLOBAL_MOUSE_UP")
	overlay:Show()
	self:UpdateDropTarget()
end

function SettingsIntegration:FinishDrag()
	if not self.dragState or not self.dragState.entryID then
		return
	end

	if self.dragOverlay then
		self.dragOverlay:UnregisterEvent("GLOBAL_MOUSE_UP")
		self.dragOverlay:Hide()
	end
	local drag = self.dragState
	if drag.proxy then
		drag.proxy:Hide()
	end

	for _, lane in ipairs(self.lanes or {}) do
		HideIndicator(lane)
		lane.Header:SetBackdropBorderColor(0.30, 0.30, 0.30, 0.95)
	end

	if drag.targetContainerID then
		local configured = EnsureEntry(drag.entryID)
		if configured then
			local targetIndex = drag.targetIndex
			if drag.sourceContainerID == drag.targetContainerID and configured.order and targetIndex and configured.order < targetIndex then
				targetIndex = targetIndex - 1
			end

			addon.Profile:InsertEntryIntoContainer(configured.id, drag.targetContainerID, targetIndex, { finalIndex = true })
			addon.Catalog:Rebuild()
			addon.Bars:RefreshRuntime()
			self:RefreshPanel()
		end
	end

	self.dragState = nil
end

function SettingsIntegration:BuildOrganizerPanel(panel)
	panel.SearchBox = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	panel.SearchBox:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 64, 8)
	panel.SearchBox:SetSize(290, 22)
	if panel.SearchBox.Instructions then
		panel.SearchBox.Instructions:SetText("Enter search text")
	end
	panel.SearchBox:SetScript("OnTextChanged", function(selfBox)
		SearchBoxTemplate_OnTextChanged(selfBox)
		panel.searchQuery = selfBox:GetText()
		SettingsIntegration:RefreshPanel()
	end)

	panel.OptionsButton = CreateFrame("DropdownButton", nil, panel, "UIPanelIconDropdownButtonTemplate")
	panel.OptionsButton:SetSize(20, 20)
	panel.OptionsButton:SetPoint("LEFT", panel.SearchBox, "RIGHT", 3, 0)
	if panel.OptionsButton.SetupMenu then
		panel.OptionsButton:SetupMenu(function(_owner, rootDescription)
			rootDescription:CreateButton(addon.Profile:IsLocked() and "Unlock Bars" or "Lock Bars", function()
				addon.Profile:SetLocked(not addon.Profile:IsLocked())
				addon.Bars:RefreshRuntime()
				SettingsIntegration:RefreshPanel()
			end)
			rootDescription:CreateButton(addon.Profile:ShowTooltips() and "Hide Runtime Tooltips" or "Show Runtime Tooltips", function()
				addon.Profile:SetShowTooltips(not addon.Profile:ShowTooltips())
				SettingsIntegration:RefreshPanel()
			end)
			rootDescription:CreateButton(addon.Profile:IsUnifiedVisualStyleEnabled() and "Disable Unified Visual Style" or "Enable Unified Visual Style", function()
				addon.Profile:SetUnifiedVisualStyleEnabled(not addon.Profile:IsUnifiedVisualStyleEnabled())
				addon.Bars:RefreshRuntime()
				if addon.CooldownViewerSkin then
					addon.CooldownViewerSkin:RefreshAll()
				end
				SettingsIntegration:RefreshPanel()
			end)
			rootDescription:CreateDivider()
			rootDescription:CreateButton("Add Spell by ID", function()
				OpenAddEntryDialog("spell")
			end)
			rootDescription:CreateButton("Add Item by ID", function()
				OpenAddEntryDialog("item")
			end)
			rootDescription:CreateButton("Add Bar", function()
				local bar, reason = addon.Profile:AddBar()
				if bar then
					addon.Bars:RefreshRuntime()
					SettingsIntegration:RefreshPanel()
				else
					addon.Print("Add bar failed: " .. tostring(reason))
				end
			end)
		end)
	else
		panel.OptionsButton:SetScript("OnClick", function()
			OpenAddEntryDialog("spell")
		end)
	end
	panel.OptionsButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:Show()
	end)
	panel.OptionsButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	panel.Scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
	panel.Scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -10)
	panel.Scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 28)

	panel.Content = CreateFrame("Frame", nil, panel.Scroll)
	panel.Content:SetSize(1, 1)
	panel.Scroll:SetScrollChild(panel.Content)
	panel.Content:EnableMouse(true)
end
