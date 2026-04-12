local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar
local util = addon.Util
local constants = addon.Constants

local Profile = {}
addon.Profile = Profile

local function SortEntries(entries)
	util.sort(entries, function(left, right)
		if left.order == right.order then
			return left.id < right.id
		end
		return left.order < right.order
	end)
end

local function NormalizeBar(bar, index)
	local normalized = util.ShallowCopy(bar or {})
	normalized.id = normalized.id or ("bar" .. tostring(index))
	normalized.name = normalized.name or ("Bar " .. tostring(index))
	normalized.point = normalized.point or "CENTER"
	normalized.relativePoint = normalized.relativePoint or normalized.point
	normalized.x = util.NumberOrNil(normalized.x) or 0
	normalized.y = util.NumberOrNil(normalized.y) or 0
	normalized.iconSize = util.NumberOrNil(normalized.iconSize) or 40
	normalized.spacing = util.NumberOrNil(normalized.spacing) or 6
	normalized.anchorTarget = normalized.anchorTarget or constants.ANCHOR_TARGET_SCREEN
	normalized.anchorSide = normalized.anchorSide or constants.ANCHOR_SIDE_BOTTOM
	normalized.growthDirection = normalized.growthDirection or constants.GROWTH_RIGHT
	normalized.enabled = normalized.enabled ~= false
	return normalized
end

local function NormalizeEntry(entry)
	local normalized = util.ShallowCopy(entry or {})
	normalized.id = normalized.id or util.MakeEntryID(normalized.kind or "spell", normalized.spellID or normalized.itemID or normalized.slotID or "unknown")
	normalized.kind = normalized.kind or "spell"
	normalized.containerID = normalized.containerID or constants.HIDDEN_CONTAINER_ID
	normalized.order = util.NumberOrNil(normalized.order) or 1
	normalized.enabled = normalized.enabled ~= false
	return normalized
end

local function NormalizeOrdersByContainer(entries)
	local buckets = {}
	for _, entry in ipairs(entries) do
		local containerID = entry.containerID or constants.HIDDEN_CONTAINER_ID
		buckets[containerID] = buckets[containerID] or {}
		buckets[containerID][#buckets[containerID] + 1] = entry
	end
	for _, bucketEntries in pairs(buckets) do
		SortEntries(bucketEntries)
		for index, entry in ipairs(bucketEntries) do
			entry.order = index
		end
	end
end

function Profile:GetProfilesTable()
	BuckleUpSidecarDB = BuckleUpSidecarDB or {}
	BuckleUpSidecarDB.profiles = BuckleUpSidecarDB.profiles or {}
	return BuckleUpSidecarDB.profiles
end

function Profile:GetAccountLayoutsTable()
	BuckleUpSidecarDB = BuckleUpSidecarDB or {}
	BuckleUpSidecarDB.layouts = BuckleUpSidecarDB.layouts or {}
	return BuckleUpSidecarDB.layouts
end

function Profile:GetCurrentCharacterKey()
	local name = UnitName("player") or "Unknown"
	local realm = GetRealmName() or "UnknownRealm"
	local className = select(2, UnitClass("player")) or "UNKNOWN"
	return string.format("%s-%s-%s", name, realm, className)
end

function Profile:NormalizeProfile(profile)
	local normalized = util.DeepCopy(addon.Defaults.profile)
	local sourceBars = (profile and profile.bars) or {}
	local sourceEntries = (profile and profile.entries) or {}
	local sourceOptions = (profile and profile.options) or {}

	normalized.bars = {}
	for index, bar in ipairs(sourceBars) do
		normalized.bars[#normalized.bars + 1] = NormalizeBar(bar, index)
	end
	if #normalized.bars == 0 then
		normalized.bars[1] = NormalizeBar(addon.Defaults.profile.bars[1], 1)
	end

	local validBarIDs = {}
	for _, bar in ipairs(normalized.bars) do
		validBarIDs[bar.id] = true
	end

	normalized.entries = {}
	for _, entry in ipairs(sourceEntries) do
		local normalizedEntry = NormalizeEntry(entry)
		if not validBarIDs[normalizedEntry.containerID] and normalizedEntry.containerID ~= constants.HIDDEN_CONTAINER_ID then
			normalizedEntry.containerID = constants.HIDDEN_CONTAINER_ID
		end
		normalized.entries[#normalized.entries + 1] = normalizedEntry
	end
	NormalizeOrdersByContainer(normalized.entries)

	normalized.options = util.ShallowCopy(normalized.options or {})
	for key, value in pairs(sourceOptions) do
		normalized.options[key] = value
	end
	if normalized.options.hidePassiveTrinkets == nil then
		normalized.options.hidePassiveTrinkets = true
	end
	if normalized.options.locked == nil then
		normalized.options.locked = false
	end
	if normalized.options.showTooltips == nil then
		normalized.options.showTooltips = true
	end
	if normalized.options.unifiedVisualStyleEnabled == nil then
		normalized.options.unifiedVisualStyleEnabled = true
	end

	return normalized
end

function Profile:RefreshProfile()
	local profiles = self:GetProfilesTable()
	local key = util.GetCurrentSpecKey()
	local normalized = self:NormalizeProfile(profiles[key])
	profiles[key] = normalized
	addon.profileKey = key
	addon.profile = normalized
	return normalized
end

function Profile:CommitProfile()
	local profiles = self:GetProfilesTable()
	profiles[addon.profileKey] = addon.profile
end

function Profile:GetBars()
	return addon.profile and addon.profile.bars or {}
end

function Profile:GetOptions()
	return addon.profile and addon.profile.options or {}
end

function Profile:IsLocked()
	return self:GetOptions().locked == true
end

function Profile:SetLocked(locked)
	local options = self:GetOptions()
	options.locked = locked == true
	self:CommitProfile()
	self:RecordLayoutSnapshot()
	return true
end

function Profile:ShowTooltips()
	return self:GetOptions().showTooltips ~= false
end

function Profile:SetShowTooltips(showTooltips)
	local options = self:GetOptions()
	options.showTooltips = showTooltips ~= false
	self:CommitProfile()
	return true
end

function Profile:IsUnifiedVisualStyleEnabled()
	return self:GetOptions().unifiedVisualStyleEnabled ~= false
end

function Profile:SetUnifiedVisualStyleEnabled(enabled)
	local options = self:GetOptions()
	options.unifiedVisualStyleEnabled = enabled ~= false
	self:CommitProfile()
	return true
end

function Profile:GetBarByID(barID)
	for _, bar in ipairs(self:GetBars()) do
		if bar.id == barID then
			return bar
		end
	end
end

function Profile:GetNextBarID()
	local nextIndex = 1
	local used = {}
	for _, bar in ipairs(self:GetBars()) do
		used[bar.id] = true
	end
	while used["bar" .. tostring(nextIndex)] do
		nextIndex = nextIndex + 1
	end
	return "bar" .. tostring(nextIndex)
end

function Profile:AddBar(name)
	local bars = self:GetBars()
	if #bars >= constants.MAX_BARS then
		return nil, "max_bars"
	end
	local newBar = NormalizeBar({
		id = self:GetNextBarID(),
		name = name or ("Bar " .. tostring(#bars + 1)),
		x = 0,
		y = -180 - (#bars * 52),
	}, #bars + 1)
	bars[#bars + 1] = newBar
	self:CommitProfile()
	self:RecordLayoutSnapshot()
	return newBar
end

function Profile:DeleteBar(barID)
	local bars = self:GetBars()
	if #bars <= 1 then
		return false, "last_bar"
	end
	local removedIndex
	for index, bar in ipairs(bars) do
		if bar.id == barID then
			removedIndex = index
			break
		end
	end
	if not removedIndex then
		return false, "missing_bar"
	end
	util.tremove(bars, removedIndex)

	for _, entry in ipairs(addon.profile.entries) do
		if entry.containerID == barID then
			entry.containerID = constants.HIDDEN_CONTAINER_ID
			entry.order = 9999
		end
	end
	self:NormalizeOrders()
	self:CommitProfile()
	self:RecordLayoutSnapshot()
	return true
end

function Profile:RenameBar(barID, name)
	local bar = self:GetBarByID(barID)
	if not bar then
		return false
	end
	bar.name = name or bar.name
	self:CommitProfile()
	self:RecordLayoutSnapshot()
	return true
end

function Profile:UpdateBarLayout(barID, fields)
	local bar = self:GetBarByID(barID)
	if not bar then
		return false
	end
	for key, value in pairs(fields or {}) do
		bar[key] = value
	end
	self:CommitProfile()
	self:RecordLayoutSnapshot()
	return true
end

function Profile:NormalizeOrders()
	NormalizeOrdersByContainer(addon.profile.entries)
end

function Profile:GetConfiguredEntries()
	return addon.profile and addon.profile.entries or {}
end

function Profile:GetEntryByID(entryID)
	for _, entry in ipairs(self:GetConfiguredEntries()) do
		if entry.id == entryID then
			return entry
		end
	end
end

function Profile:GetEntryByKindAndRawID(kind, rawID)
	return self:GetEntryByID(util.MakeEntryID(kind, rawID))
end

function Profile:EnsureEntry(entryData)
	local entryID = entryData.id or util.MakeEntryID(entryData.kind, entryData.spellID or entryData.itemID or entryData.slotID)
	local existing = self:GetEntryByID(entryID)
	if existing then
		for key, value in pairs(entryData) do
			if value ~= nil then
				existing[key] = value
			end
		end
		self:CommitProfile()
		return existing
	end

	local newEntry = NormalizeEntry(entryData)
	local entries = self:GetConfiguredEntries()
	entries[#entries + 1] = newEntry
	self:NormalizeOrders()
	self:CommitProfile()
	return newEntry
end

function Profile:RemoveEntry(entryID)
	local entries = self:GetConfiguredEntries()
	for index, entry in ipairs(entries) do
		if entry.id == entryID then
			if entry.kind == "trinketSlot" then
				return false, "protected_entry"
			end
			util.tremove(entries, index)
			self:NormalizeOrders()
			self:CommitProfile()
			return true
		end
	end
	return false, "missing_entry"
end

function Profile:SetEntryContainer(entryID, containerID)
	local entry = self:GetEntryByID(entryID)
	if not entry then
		return false, "missing_entry"
	end
	if containerID ~= constants.HIDDEN_CONTAINER_ID and not self:GetBarByID(containerID) then
		return false, "missing_bar"
	end
	entry.containerID = containerID
	entry.order = 9999
	self:NormalizeOrders()
	self:CommitProfile()
	return true
end

function Profile:InsertEntryIntoContainer(entryID, containerID, targetIndex, options)
	local entry = self:GetEntryByID(entryID)
	if not entry then
		return false, "missing_entry"
	end
	if containerID ~= constants.HIDDEN_CONTAINER_ID and not self:GetBarByID(containerID) then
		return false, "missing_bar"
	end

	local containerEntries = self:GetEntriesForContainer(containerID)
	local sourceContainerID = entry.containerID
	local sourceIndex
	for index, current in ipairs(containerEntries) do
		if current.id == entryID then
			sourceIndex = index
			break
		end
	end

	entry.containerID = containerID

	local remainingEntries = {}
	for _, current in ipairs(containerEntries) do
		if current.id ~= entryID then
			remainingEntries[#remainingEntries + 1] = current
		end
	end

	targetIndex = util.NumberOrNil(targetIndex) or (#remainingEntries + 1)
	if not (options and options.finalIndex == true) and sourceContainerID == containerID and sourceIndex and targetIndex > sourceIndex then
		targetIndex = targetIndex - 1
	end
	targetIndex = math.max(1, math.min(targetIndex, #remainingEntries + 1))
	table.insert(remainingEntries, targetIndex, entry)

	for index, current in ipairs(remainingEntries) do
		current.order = index
	end

	if sourceContainerID ~= containerID then
		local sourceEntries = self:GetEntriesForContainer(sourceContainerID)
		for index, current in ipairs(sourceEntries) do
			current.order = index
		end
	end

	self:CommitProfile()
	return true
end

function Profile:MoveEntry(entryID, direction)
	local entry = self:GetEntryByID(entryID)
	if not entry then
		return false, "missing_entry"
	end
	local entries = self:GetEntriesForContainer(entry.containerID)
	local currentIndex
	for index, current in ipairs(entries) do
		if current.id == entryID then
			currentIndex = index
			break
		end
	end
	if not currentIndex then
		return false, "missing_index"
	end
	local targetIndex = direction == "up" and (currentIndex - 1) or (currentIndex + 1)
	if targetIndex < 1 or targetIndex > #entries then
		return false, "out_of_bounds"
	end
	local other = entries[targetIndex]
	entry.order, other.order = other.order, entry.order
	self:NormalizeOrders()
	self:CommitProfile()
	return true
end

function Profile:GetEntriesForContainer(containerID)
	local matches = {}
	for _, entry in ipairs(self:GetConfiguredEntries()) do
		if entry.containerID == containerID then
			matches[#matches + 1] = entry
		end
	end
	SortEntries(matches)
	return matches
end

function Profile:RecordLayoutSnapshot()
	local specKey = addon.profileKey or util.GetCurrentSpecKey()
	local layouts = self:GetAccountLayoutsTable()
	layouts[tostring(specKey)] = {
		label = util.GetSpecNameFromKey(specKey),
		specKey = tostring(specKey),
		bars = util.DeepCopy(self:GetBars()),
	}
end

function Profile:GetSnapshotByKey(snapshotKey)
	if not snapshotKey then
		return nil
	end

	local normalizedKey = tostring(snapshotKey)
	local profileSnapshot = self:GetProfilesTable()[normalizedKey]
	if profileSnapshot and type(profileSnapshot.bars) == "table" then
		return {
			key = normalizedKey,
			label = util.GetSpecNameFromKey(normalizedKey),
			specKey = normalizedKey,
			bars = util.DeepCopy(profileSnapshot.bars or {}),
		}
	end

	local storedSnapshot = self:GetAccountLayoutsTable()[normalizedKey]
	if storedSnapshot and type(storedSnapshot.bars) == "table" then
		return {
			key = normalizedKey,
			label = storedSnapshot.label or util.GetSpecNameFromKey(normalizedKey),
			specKey = tostring(storedSnapshot.specKey or normalizedKey),
			bars = util.DeepCopy(storedSnapshot.bars or {}),
		}
	end

	return nil
end

function Profile:GetLayoutSnapshots()
	local layouts = self:GetAccountLayoutsTable()
	local profiles = self:GetProfilesTable()
	local snapshots = {}
	local seen = {}

	for specKey, profile in pairs(profiles) do
		if type(profile) == "table" and type(profile.bars) == "table" then
			local snapshotKey = tostring(specKey)
			snapshots[#snapshots + 1] = {
				key = snapshotKey,
				label = util.GetSpecNameFromKey(specKey),
				specKey = tostring(specKey),
				bars = util.DeepCopy(profile.bars or {}),
			}
			seen[snapshotKey] = true
		end
	end

	for snapshotKey, snapshot in pairs(layouts) do
		if not seen[snapshotKey] then
			snapshots[#snapshots + 1] = {
				key = snapshotKey,
				label = snapshot.label or util.GetSpecNameFromKey(snapshotKey),
				specKey = tostring(snapshot.specKey or snapshotKey),
				bars = util.DeepCopy(snapshot.bars or {}),
			}
		end
	end
	util.sort(snapshots, function(left, right)
		return left.label < right.label
	end)
	return snapshots
end

function Profile:ApplyLayoutSnapshot(snapshotKey)
	local snapshot = self:GetSnapshotByKey(snapshotKey)
	if not snapshot or type(snapshot.bars) ~= "table" then
		return false, "missing_snapshot"
	end

	addon.profile.bars = {}
	for index, bar in ipairs(snapshot.bars) do
		addon.profile.bars[index] = NormalizeBar(bar, index)
	end
	if #addon.profile.bars == 0 then
		addon.profile.bars[1] = NormalizeBar(addon.Defaults.profile.bars[1], 1)
	end

	local validBarIDs = {}
	for _, bar in ipairs(addon.profile.bars) do
		validBarIDs[bar.id] = true
	end
	for _, entry in ipairs(addon.profile.entries) do
		if not validBarIDs[entry.containerID] and entry.containerID ~= constants.HIDDEN_CONTAINER_ID then
			entry.containerID = constants.HIDDEN_CONTAINER_ID
		end
	end

	self:NormalizeOrders()
	self:CommitProfile()
	self:RecordLayoutSnapshot()
	return true
end
