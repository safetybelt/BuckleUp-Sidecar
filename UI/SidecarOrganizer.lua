local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar

local SettingsIntegration = addon.SettingsIntegration or {}
addon.SettingsIntegration = SettingsIntegration

local TILE_SIZE = 38
local TILE_GAP = 8
local LANE_PADDING = 10
local HEADER_HEIGHT = 22
local LANE_WIDTH = 344
local LANE_CONTAINER_WIDTH = 315
local LANE_CONTAINER_LEFT = 13
local LANE_CONTAINER_TOP = 15
local LANE_CONTAINER_BOTTOM = 10
local MIN_LANE_CONTENT_HEIGHT = TILE_SIZE
local SEARCH_LEFT_INSET = 72
local SEARCH_TOP_INSET = 30
local SEARCH_WIDTH = 290
local SEARCH_HEIGHT = 30
local SCROLL_LEFT_INSET = 17
local SCROLL_RIGHT_INSET = 30
local SCROLL_TOP_INSET = 72
local SCROLL_BOTTOM_INSET = 24

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

local function SetLaneHeaderHover(lane, isHovering)
	if not lane or not lane.Header then
		return
	end

	if isHovering then
		if lane.Header.LockHighlight then
			lane.Header:LockHighlight()
		end
	else
		if lane.Header.UnlockHighlight then
			lane.Header:UnlockHighlight()
		end
	end
end

local function ApplyLaneCollapsedState(lane, collapsed)
	if not lane then
		return
	end

	lane.collapsed = collapsed == true
	if lane.Header and lane.Header.UpdateCollapsedState then
		lane.Header:UpdateCollapsedState(lane.collapsed)
	end
	if lane.Container then
		lane.Container:SetShown(not lane.collapsed)
	end
	if lane.collapsed then
		HideIndicator(lane)
		lane:SetHeight(HEADER_HEIGHT)
	else
		local contentHeight = lane.Container and lane.Container:GetHeight() or MIN_LANE_CONTENT_HEIGHT
		lane:SetHeight(HEADER_HEIGHT + LANE_CONTAINER_TOP + contentHeight + LANE_CONTAINER_BOTTOM)
	end
end

local function IsCursorOverExternalDropSurface(lane)
	if not lane or not lane.acceptsExternalDrop then
		return false
	end

	return IsCursorOverFrame(lane.Header) or IsCursorOverFrame(lane.Container)
end

local function AddCustomEntryByKind(kind, rawID, onComplete)
	return addon.EntryIntake:AddByKind(kind, rawID, { onComplete = onComplete })
end

local function OpenLaneNameEditor(lane)
	if not lane or not lane.containerID or lane.containerID == addon.Constants.HIDDEN_CONTAINER_ID then
		return
	end

	if lane.Header and lane.Header.Name then
		lane.Header.Name:Hide()
	end
	if lane.Title then
		lane.Title:Hide()
	end
	lane.NameEditor:SetText(lane.currentLabel or lane.Title:GetText() or "")
	lane.NameEditor:Show()
	lane.NameEditor:SetFocus()
	lane.NameEditor:HighlightText()
end

local function OpenLaneDeleteDialog(lane)
	if not lane or not lane.containerID or lane.containerID == addon.Constants.HIDDEN_CONTAINER_ID then
		return
	end

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
		popup.barID = lane.containerID
	end
end

local function OpenLaneHeaderContextMenu(lane)
	if not lane or not lane.containerID or lane.containerID == addon.Constants.HIDDEN_CONTAINER_ID then
		return
	end

	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(lane.Header, function(_owner, rootDescription)
			rootDescription:CreateButton("Rename", function()
				OpenLaneNameEditor(lane)
			end)
			rootDescription:CreateButton("Delete", function()
				OpenLaneDeleteDialog(lane)
			end)
		end)
	else
		OpenLaneNameEditor(lane)
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

local function OpenBlizzardEditMode()
	if not EditModeManagerFrame and type(UIParentLoadAddOn) == "function" then
		UIParentLoadAddOn("Blizzard_EditMode")
	end

	if not EditModeManagerFrame then
		if addon.Print then
			addon.Print("Blizzard Edit Mode is not available.")
		end
		return
	end

	if EditModeManagerFrame.CanEnterEditMode and not EditModeManagerFrame:CanEnterEditMode() then
		if addon.Print then
			addon.Print("Blizzard Edit Mode can't be opened right now.")
		end
		return
	end

	ShowUIPanel(EditModeManagerFrame)
end

function SettingsIntegration:OpenAddEntryDialog()
	if addon.AddEntryDialog then
		addon.AddEntryDialog:Open()
	end
end

function SettingsIntegration:OpenBlizzardEditMode()
	OpenBlizzardEditMode()
end

function SettingsIntegration:GetOrganizerRows()
	local rows = {}
	local bars = addon.Profile:GetBars()
	for _, bar in ipairs(bars) do
		rows[#rows + 1] = {
			rowType = "lane",
			containerID = bar.id,
			label = bar.name,
		}
	end
	if #bars < (addon.Constants.MAX_BARS or math.huge) then
		rows[#rows + 1] = {
			rowType = "action",
			actionID = "addBar",
			label = "Add New Bar",
		}
	end
	rows[#rows + 1] = {
		rowType = "lane",
		containerID = addon.Constants.HIDDEN_CONTAINER_ID,
		label = "Not Displayed",
	}
	return rows
end

function SettingsIntegration:GetLaneAtIndex(index)
	self.lanes = self.lanes or {}
	local lane = self.lanes[index]
	if not lane then
		lane = self:CreateLane(self.panel.Content)
		self.lanes[index] = lane
	end
	return lane
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
		if addon.Catalog:ShouldShowInOrganizer(entry, configured) then
			local containerID = (configured and configured.containerID) or addon.Constants.HIDDEN_CONTAINER_ID
			entriesByContainer[containerID] = entriesByContainer[containerID] or {}
			entriesByContainer[containerID][#entriesByContainer[containerID] + 1] = entry
		end
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

	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAllPoints()

	button.Highlight = button:CreateTexture(nil, "HIGHLIGHT")
	button.Highlight:SetAllPoints()
	button.Highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	button.Highlight:SetBlendMode("ADD")
	button.Highlight:SetAlpha(0.4)

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
	lane:SetWidth(LANE_WIDTH)
	lane.tiles = {}

	lane.Header = CreateFrame("Button", nil, lane, "ListHeaderThreeSliceTemplate")
	lane.Header:SetHeight(HEADER_HEIGHT)
	lane.Header:SetPoint("TOPLEFT", lane, "TOPLEFT")
	lane.Header:SetPoint("TOPRIGHT", lane, "TOPRIGHT")
	lane.Header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	if lane.Header.SetTitleColor then
		lane.Header:SetTitleColor(false, NORMAL_FONT_COLOR)
		lane.Header:SetTitleColor(true, NORMAL_FONT_COLOR)
	end
	if lane.Header.SetClickHandler then
		lane.Header:SetClickHandler(function(_, button)
			if button == "LeftButton" then
				ApplyLaneCollapsedState(lane, not lane.collapsed)
				SettingsIntegration:RefreshPanel()
			elseif button == "RightButton" then
				OpenLaneHeaderContextMenu(lane)
			end
		end)
	else
		lane.Header:SetScript("OnClick", function(_, button)
			if button == "LeftButton" then
				ApplyLaneCollapsedState(lane, not lane.collapsed)
				SettingsIntegration:RefreshPanel()
			elseif button == "RightButton" then
				OpenLaneHeaderContextMenu(lane)
			end
		end)
	end

	lane.Title = lane.Header.Text or lane.Header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	if not lane.Header.Text then
		lane.Title:SetPoint("LEFT", lane.Header, "LEFT", 8, 0)
	end
	lane.Title:SetTextColor(1, 0.82, 0)
	lane.Container = CreateFrame("Frame", nil, lane)
	lane.Container:SetPoint("TOPLEFT", lane.Header, "BOTTOMLEFT", LANE_CONTAINER_LEFT, -LANE_CONTAINER_TOP)
	lane.Container:SetWidth(LANE_CONTAINER_WIDTH)
	lane.Container:SetHeight(MIN_LANE_CONTENT_HEIGHT)
	lane.Container:EnableMouse(true)
	lane.Container:SetScript("OnReceiveDrag", function()
		if lane.acceptsExternalDrop then
			SettingsIntegration:TryHandleExternalDrop(lane)
		end
	end)
	lane.Container:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" and lane.acceptsExternalDrop then
			SettingsIntegration:TryHandleExternalDrop(lane)
		end
	end)

	lane.Description = lane.Container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	lane.Description:SetPoint("TOPLEFT", lane.Container, "TOPLEFT", 0, 0)
	lane.Description:SetPoint("TOPRIGHT", lane.Container, "TOPRIGHT", 0, 0)
	lane.Description:SetJustifyH("LEFT")
	lane.Description:SetTextColor(0.72, 0.72, 0.72)
	lane.Description:SetText("Drag spells or items here to add them to your catalog")
	lane.Description:Hide()

	lane.NameEditor = CreateFrame("EditBox", nil, lane, "InputBoxTemplate")
	lane.NameEditor:SetSize(150, 20)
	lane.NameEditor:SetAutoFocus(false)
	lane.NameEditor:Hide()
	lane.NameEditor:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		self:Hide()
		if self.lane then
			if self.lane.Header and self.lane.Header.Name then
				self.lane.Header.Name:Show()
			end
			if self.lane.Title then
				self.lane.Title:Show()
			end
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
			if self.lane.Header and self.lane.Header.Name then
				self.lane.Header.Name:Show()
			end
			if self.lane.Title then
				self.lane.Title:Show()
			end
		end
	end)

	lane.Indicator = lane.Container:CreateTexture(nil, "OVERLAY")
	lane.Indicator:SetColorTexture(1, 0.82, 0, 0.95)
	lane.Indicator:SetWidth(4)
	lane.Indicator:Hide()
	return lane
end

function SettingsIntegration:CreateAddBarRow(parent)
	local row = CreateFrame("Button", nil, parent, "ListHeaderThreeSliceTemplate")
	row:SetHeight(HEADER_HEIGHT)
	row:SetWidth(LANE_WIDTH)
	row:SetMotionScriptsWhileDisabled(true)
	local accentR, accentG, accentB = 0.34, 0.78, 0.48
	if row.SetTitleColor then
		local accentColor = CreateColor(accentR, accentG, accentB)
		row:SetTitleColor(false, accentColor)
		row:SetTitleColor(true, accentColor)
	end
	if row.SetHeaderText then
		row:SetHeaderText("Add New Bar")
	end
	if row.Name then
		row.Name:SetAlpha(1)
		row.Name:SetTextColor(accentR, accentG, accentB)
	end
	if row.Left then
		row.Left:SetAlpha(0.65)
		row.Left:SetVertexColor(accentR, accentG, accentB, 1)
	end
	if row.Middle then
		row.Middle:SetAlpha(0.65)
		row.Middle:SetVertexColor(accentR, accentG, accentB, 1)
	end
	if row.Right then
		row.Right:SetAtlas("Options_ListExpand_Right", true)
		row.Right:SetAlpha(0.65)
		row.Right:SetVertexColor(accentR, accentG, accentB, 1)
	end
	if row.HighlightLeft then
		row.HighlightLeft:SetAlpha(0.35)
		row.HighlightLeft:SetVertexColor(accentR, accentG, accentB, 1)
	end
	if row.HighlightMiddle then
		row.HighlightMiddle:SetAlpha(0.35)
		row.HighlightMiddle:SetVertexColor(accentR, accentG, accentB, 1)
	end
	if row.HighlightRight then
		row.HighlightRight:SetAtlas("Options_ListExpand_Right", true)
		row.HighlightRight:SetAlpha(0.35)
		row.HighlightRight:SetVertexColor(accentR, accentG, accentB, 1)
	end
	row:SetScript("OnClick", function()
		local bar, reason = addon.Profile:AddBar()
		if bar then
			addon.Bars:RefreshRuntime()
			SettingsIntegration:RefreshPanel()
		else
			addon.Print("Add bar failed: " .. tostring(reason))
		end
	end)
	return row
end

function SettingsIntegration:LayoutLane(lane, entries)
	if lane.Header and lane.Header.UpdateCollapsedState then
		lane.Header:UpdateCollapsedState(lane.collapsed == true)
	end
	local descriptionHeight = lane.Description and lane.Description:IsShown() and 18 or 0
	local contentWidth = math.max(240, lane.Container:GetWidth() > 0 and lane.Container:GetWidth() or LANE_CONTAINER_WIDTH)
	local columns = math.max(1, math.floor((contentWidth + TILE_GAP) / (TILE_SIZE + TILE_GAP)))

	for index, entry in ipairs(entries) do
		local tile = lane.tiles[index]
		if not tile then
			tile = self:CreateTile(lane.Container)
			tile.lane = lane
			tile:SetScript("OnReceiveDrag", function(selfTile)
				if selfTile.lane and selfTile.lane.acceptsExternalDrop then
					SettingsIntegration:TryHandleExternalDrop(selfTile.lane)
				end
			end)
			lane.tiles[index] = tile
		end

		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", lane.Container, "TOPLEFT", column * (TILE_SIZE + TILE_GAP), -descriptionHeight - (row * (TILE_SIZE + TILE_GAP)))

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
				if not self:TryHandleExternalDrop() then
					self:FinishDrag()
				end
			end
		end)
		tile:Show()
	end

	for index = #entries + 1, #lane.tiles do
		lane.tiles[index]:Hide()
	end

	local rows = math.max(1, math.floor((#entries - 1) / columns) + 1)
	local contentHeight = math.max(MIN_LANE_CONTENT_HEIGHT, descriptionHeight + (rows * TILE_SIZE) + ((rows - 1) * TILE_GAP))
	lane.Container:SetHeight(contentHeight)
	ApplyLaneCollapsedState(lane, lane.collapsed)
end

function SettingsIntegration:RefreshLanes()
	if not self.panel or not self.panel:IsShown() then
		return
	end

	self:RebuildOrganizerEntryCache()

	self.panel.Content:SetWidth(LANE_WIDTH)

	local rows = self:GetOrganizerRows()
	self.addBarRow = self.addBarRow or self:CreateAddBarRow(self.panel.Content)
	local previousLane
	local activeLaneCount = 0
	for _, row in ipairs(rows) do
		if row.rowType == "action" and row.actionID == "addBar" then
			local row = self.addBarRow
			row:ClearAllPoints()
			if previousLane then
				row:SetPoint("TOPLEFT", previousLane, "BOTTOMLEFT", 0, -LANE_PADDING)
				row:SetPoint("TOPRIGHT", previousLane, "BOTTOMRIGHT", 0, -LANE_PADDING)
			else
				row:SetPoint("TOPLEFT", self.panel.Content, "TOPLEFT", 0, 0)
				row:SetPoint("TOPRIGHT", self.panel.Content, "TOPRIGHT", 0, 0)
			end
			row:Show()
			previousLane = row
		elseif row.rowType == "lane" then
			activeLaneCount = activeLaneCount + 1
			local lane = self:GetLaneAtIndex(activeLaneCount)
			lane.containerID = row.containerID
			lane:ClearAllPoints()
			if previousLane then
				lane:SetPoint("TOPLEFT", previousLane, "BOTTOMLEFT", 0, -LANE_PADDING)
				lane:SetPoint("TOPRIGHT", previousLane, "BOTTOMRIGHT", 0, -LANE_PADDING)
			else
				lane:SetPoint("TOPLEFT", self.panel.Content, "TOPLEFT", 0, 0)
			end

			local entries = self:GetEntriesForContainer(row.containerID)
			lane.currentLabel = row.label
			if lane.Header.SetHeaderText then
				lane.Header:SetHeaderText(row.label)
			else
				lane.Title:SetText(row.label)
			end
			lane.NameEditor.lane = lane
			lane.NameEditor:ClearAllPoints()
			lane.NameEditor:SetPoint("LEFT", lane.Header, "LEFT", 6, 0)
			lane.acceptsExternalDrop = row.containerID == addon.Constants.HIDDEN_CONTAINER_ID
			lane.NameEditor:Hide()
			lane.Title:Show()
			lane.Description:SetShown(row.containerID == addon.Constants.HIDDEN_CONTAINER_ID)
			self:LayoutLane(lane, entries)
			lane:Show()
			previousLane = lane
		end
	end

	for index, lane in ipairs(self.lanes or {}) do
		if index > activeLaneCount then
			lane:Hide()
		end
	end
	if self.addBarRow and not previousLane then
		self.addBarRow:Hide()
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

function SettingsIntegration:GetHiddenLane()
	for _, lane in ipairs(self.lanes or {}) do
		if lane.containerID == addon.Constants.HIDDEN_CONTAINER_ID then
			return lane
		end
	end
end

function SettingsIntegration:ClearExternalDropTarget()
	local hiddenLane = self:GetHiddenLane()
	if hiddenLane and hiddenLane:IsShown() then
		hiddenLane.Header:SetAlpha(1)
		hiddenLane.Container:SetAlpha(1)
	end
	self.externalDropTargetActive = nil
end

function SettingsIntegration:ResolveSpellCursorID(cursorData1, cursorData2, cursorData4)
	local numericCursorID = addon.Util.NumberOrNil(cursorData1) or addon.Util.NumberOrNil(cursorData2)
	local explicitSpellID = addon.Util.NumberOrNil(cursorData4)
	if explicitSpellID and addon.Util.IsValidSpellID(explicitSpellID) then
		return explicitSpellID
	end

	local bookType = type(cursorData2) == "string" and cursorData2 or nil

	-- Spellbook drags can expose the spellbook slot/index in cursorData1.
	-- Resolve through the spellbook API first so we don't mistake a slot like 134
	-- for an unrelated valid spell ID.
	if numericCursorID and bookType and type(GetSpellBookItemInfo) == "function" then
		local _, spellID = GetSpellBookItemInfo(numericCursorID, bookType)
		local resolvedSpellID = addon.Util.NumberOrNil(spellID)
		if resolvedSpellID and addon.Util.IsValidSpellID(resolvedSpellID) then
			return resolvedSpellID
		end
	end

	if numericCursorID and addon.Util.IsValidSpellID(numericCursorID) then
		return numericCursorID
	end
end

function SettingsIntegration:GetExternalCursorEntry()
	local cursorType, cursorData1, cursorData2, cursorData4 = GetCursorInfo()
	local numericCursorID = addon.Util.NumberOrNil(cursorData1) or addon.Util.NumberOrNil(cursorData2)
	if cursorType == "spell" then
		local spellID = self:ResolveSpellCursorID(cursorData1, cursorData2, cursorData4)
		if not spellID then
			return nil
		end
		return {
			kind = "spell",
			id = spellID,
			icon = addon.Util.GetSpellTextureSafe(spellID),
			name = addon.Util.GetSpellNameSafe(spellID),
		}
	end

	if cursorType == "item" and numericCursorID then
		if not addon.Util.DoesItemExistSafe(numericCursorID) and type(cursorData2) == "string" then
			numericCursorID = tonumber(cursorData2:match("item:(%d+)")) or numericCursorID
		end
		return {
			kind = "item",
			id = numericCursorID,
			icon = addon.Util.GetItemIconSafe(numericCursorID),
			name = addon.Util.GetItemNameSafe(numericCursorID),
		}
	end
end

function SettingsIntegration:UpdateExternalDropTarget()
	if not self.panel or not self.panel:IsShown() or (self.dragState and self.dragState.entryID) then
		self:ClearExternalDropTarget()
		return
	end

	local cursorEntry = self:GetExternalCursorEntry()
	if not cursorEntry then
		self:ClearExternalDropTarget()
		return
	end

	local isOverOrganizer = IsCursorOverFrame(self.panel) or IsCursorOverFrame(self.panel.Scroll) or IsCursorOverFrame(self.panel.Content)
	if not isOverOrganizer then
		for _, lane in ipairs(self.lanes or {}) do
			if lane:IsShown() and IsCursorOverFrame(lane) then
				isOverOrganizer = true
				break
			end
		end
	end

	local hiddenLane = self:GetHiddenLane()
	if not hiddenLane or not hiddenLane:IsShown() then
		self.externalDropTargetActive = nil
		return
	end

	if isOverOrganizer and IsCursorOverExternalDropSurface(hiddenLane) then
		hiddenLane.Header:SetAlpha(1)
		hiddenLane.Container:SetAlpha(1)
		self.externalDropTargetActive = true
	else
		self:ClearExternalDropTarget()
	end
end

function SettingsIntegration:TryHandleExternalDrop(targetLane)
	if self.dragState and self.dragState.entryID then
		return false
	end

	local cursorEntry = self:GetExternalCursorEntry()
	if not cursorEntry then
		return false
	end

	local hiddenLane = targetLane
	if not hiddenLane or hiddenLane.containerID ~= addon.Constants.HIDDEN_CONTAINER_ID then
		hiddenLane = self:GetHiddenLane()
	end
	if not hiddenLane or not hiddenLane:IsShown() or not IsCursorOverExternalDropSurface(hiddenLane) then
		return false
	end

	AddCustomEntryByKind(cursorEntry.kind, cursorEntry.id, function(success)
		if success and type(ClearCursor) == "function" then
			ClearCursor()
		end
	end)
	self:ClearExternalDropTarget()
	return true
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
		SetLaneHeaderHover(lane, false)
		if lane:IsShown() and IsCursorOverFrame(lane) then
			SetLaneHeaderHover(lane, true)
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
		SetLaneHeaderHover(lane, false)
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
	local settings = self:GetSettingsFrame()

	panel.SearchBox = CreateFrame("EditBox", nil, settings, "SearchBoxTemplate")
	panel.SearchBox:SetPoint("TOPLEFT", settings, "TOPLEFT", SEARCH_LEFT_INSET, -SEARCH_TOP_INSET)
	panel.SearchBox:SetSize(SEARCH_WIDTH, SEARCH_HEIGHT)
	panel.SearchBox:Hide()
	if panel.SearchBox.Instructions then
		panel.SearchBox.Instructions:SetText("Enter search text")
	end
	panel.SearchBox:SetScript("OnTextChanged", function(selfBox)
		SearchBoxTemplate_OnTextChanged(selfBox)
		panel.searchQuery = selfBox:GetText()
		SettingsIntegration:RefreshPanel()
	end)

	panel.OptionsButton = CreateFrame("DropdownButton", nil, settings, "UIPanelIconDropdownButtonTemplate")
	panel.OptionsButton:SetSize(20, 20)
	panel.OptionsButton:SetPoint("LEFT", panel.SearchBox, "RIGHT", 3, 0)
	panel.OptionsButton:Hide()
	if panel.OptionsButton.SetupMenu then
		panel.OptionsButton:SetupMenu(function(_owner, rootDescription)
			rootDescription:CreateCheckbox("Show Tooltip", function()
				return addon.Profile:ShowTooltips()
			end, function()
				addon.Profile:SetShowTooltips(not addon.Profile:ShowTooltips())
				SettingsIntegration:RefreshPanel()
			end)
			rootDescription:CreateCheckbox("Show Full Catalog", function()
				return addon.Catalog:IsFullCatalogViewEnabled()
			end, function()
				addon.Catalog:SetFullCatalogViewEnabled(not addon.Catalog:IsFullCatalogViewEnabled())
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
			rootDescription:CreateButton("Edit Mode", function()
				SettingsIntegration:OpenBlizzardEditMode()
			end)
			rootDescription:CreateDivider()
			rootDescription:CreateButton("Add by ID", function()
				SettingsIntegration:OpenAddEntryDialog()
			end)
		end)
	else
		panel.OptionsButton:SetScript("OnClick", function()
			SettingsIntegration:OpenAddEntryDialog()
		end)
	end
	panel.OptionsButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:Show()
	end)
	panel.OptionsButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	panel.Scroll = CreateFrame("ScrollFrame", nil, settings, "ScrollFrameTemplate")
	panel.Scroll:SetPoint("TOPLEFT", settings, "TOPLEFT", SCROLL_LEFT_INSET, -SCROLL_TOP_INSET)
	panel.Scroll:SetPoint("BOTTOMRIGHT", settings, "BOTTOMRIGHT", -SCROLL_RIGHT_INSET, SCROLL_BOTTOM_INSET)
	panel.Scroll:Hide()

	panel.Content = CreateFrame("Frame", nil, panel.Scroll)
	panel.Content:SetSize(1, 1)
	panel.Scroll:SetScrollChild(panel.Content)
	panel.Content:EnableMouse(true)
	-- External spell/item drags do not expose a clean event-driven hover lifecycle for
	-- this organizer surface. We intentionally use a narrow local poll here after
	-- testing hover-only and gated variants: they behaved the same in practice, and
	-- the always-local poll stayed smaller and easier to reason about.
	panel.Content:SetScript("OnUpdate", function()
		SettingsIntegration:UpdateExternalDropTarget()
	end)
end
