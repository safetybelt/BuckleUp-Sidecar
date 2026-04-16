local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar
local util = addon.Util
local constants = addon.Constants
local barPresentation = addon.BarPresentation

local Profile = {}
addon.Profile = Profile

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
	normalized.relativeTo = type(normalized.relativeTo) == "string" and normalized.relativeTo or "UIParent"
	normalized.x = util.NumberOrNil(normalized.x) or 0
	normalized.y = util.NumberOrNil(normalized.y) or 0
	local normalizedPresentation = barPresentation:NormalizeStoredFields({
		sizePercent = util.NumberOrNil(normalized.sizePercent),
		padding = util.NumberOrNil(normalized.padding),
		opacity = util.NumberOrNil(normalized.opacity),
		visibility = normalized.visibility,
		matchMode = normalized.matchMode,
	})
	normalized.sizePercent = normalizedPresentation.sizePercent
	normalized.padding = normalizedPresentation.padding
	normalized.opacity = normalizedPresentation.opacity
	normalized.visibility = normalizedPresentation.visibility
	normalized.matchMode = normalizedPresentation.matchMode
	normalized.growthDirection = normalized.growthDirection or constants.GROWTH_RIGHT
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
	self:InitializeDatabase()
	local characterKey = self:GetCurrentCharacterKey()
	BuckleUpSidecarDB.assignments[characterKey] = BuckleUpSidecarDB.assignments[characterKey] or {}
	return BuckleUpSidecarDB.assignments[characterKey]
end

function Profile:GetAccountLayoutsTable()
	BuckleUpSidecarDB = BuckleUpSidecarDB or {}
	self:InitializeDatabase()
	BuckleUpSidecarDB.layoutSnapshots = BuckleUpSidecarDB.layoutSnapshots or {}
	return BuckleUpSidecarDB.layoutSnapshots
end

function Profile:GetCurrentCharacterKey()
	return util.GetCurrentCharacterKey()
end

function Profile:InitializeDatabase()
	BuckleUpSidecarDB = BuckleUpSidecarDB or {}
	BuckleUpSidecarDB.assignments = BuckleUpSidecarDB.assignments or {}
	BuckleUpSidecarDB.layoutSnapshots = BuckleUpSidecarDB.layoutSnapshots or {}
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

function Profile:ForEachStoredProfile(callback)
	if type(callback) ~= "function" then
		return
	end

	self:InitializeDatabase()
	for characterKey, profiles in pairs(BuckleUpSidecarDB.assignments or {}) do
		if type(profiles) == "table" then
			for specKey, profile in pairs(profiles) do
				if type(profile) == "table" then
					callback(profile, characterKey, tostring(specKey))
				end
			end
		end
	end
end

function Profile:NormalizeOrdersForEntries(entries)
	NormalizeOrdersByContainer(entries or {})
end

function Profile:MakeSnapshotKey(characterKey, specKey)
	return string.format("%s::%s", tostring(characterKey or self:GetCurrentCharacterKey()), tostring(specKey or util.GetCurrentSpecKey()))
end

function Profile:SplitSnapshotKey(snapshotKey)
	local normalizedKey = tostring(snapshotKey or "")
	local characterKey, specKey = normalizedKey:match("^(.-)::(.-)$")
	if characterKey and specKey and characterKey ~= "" and specKey ~= "" then
		return characterKey, specKey
	end
	return nil, normalizedKey ~= "" and normalizedKey or nil
end

function Profile:GetCharacterDisplayName(characterKey)
	local name, realm = tostring(characterKey or ""):match("^(.-)%-(.-)%-.+$")
	if name and realm then
		return string.format("%s-%s", name, realm)
	end
	return tostring(characterKey or "Unknown")
end

function Profile:BuildSnapshotLabel(characterKey, specKey)
	return string.format("%s (%s)", util.GetSpecNameFromKey(specKey), self:GetCharacterDisplayName(characterKey))
end

function Profile:GetBars()
	return addon.profile and addon.profile.bars or {}
end

function Profile:GetOptions()
	return addon.profile and addon.profile.options or {}
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
	local normalized = NormalizeBar(bar, 1)
	for key, value in pairs(normalized) do
		bar[key] = value
	end
	self:CommitProfile()
	self:RecordLayoutSnapshot()
	return true
end

function Profile:NormalizeOrders()
	self:NormalizeOrdersForEntries(addon.profile.entries)
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
			if entry.kind == "trinketSlot" or entry.kind == "racial" then
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
	local characterKey = self:GetCurrentCharacterKey()
	local specKey = addon.profileKey or util.GetCurrentSpecKey()
	local snapshotKey = self:MakeSnapshotKey(characterKey, specKey)
	local layouts = self:GetAccountLayoutsTable()
	layouts[snapshotKey] = {
		label = self:BuildSnapshotLabel(characterKey, specKey),
		characterKey = characterKey,
		specKey = tostring(specKey),
		bars = util.DeepCopy(self:GetBars()),
		entries = util.DeepCopy(self:GetConfiguredEntries()),
	}
end

function Profile:GetSnapshotByKey(snapshotKey)
	if not snapshotKey then
		return nil
	end

	local normalizedKey = tostring(snapshotKey)
	local requestedCharacterKey, requestedSpecKey = self:SplitSnapshotKey(normalizedKey)
	if requestedCharacterKey and BuckleUpSidecarDB and BuckleUpSidecarDB.assignments then
		local characterProfiles = BuckleUpSidecarDB.assignments[requestedCharacterKey]
		local profileSnapshot = characterProfiles and characterProfiles[requestedSpecKey]
		if profileSnapshot and type(profileSnapshot.bars) == "table" then
			return {
				key = normalizedKey,
				label = self:BuildSnapshotLabel(requestedCharacterKey, requestedSpecKey),
				characterKey = requestedCharacterKey,
				specKey = tostring(requestedSpecKey),
				bars = util.DeepCopy(profileSnapshot.bars or {}),
				entries = util.DeepCopy(profileSnapshot.entries or {}),
			}
		end
	end

	local storedSnapshot = self:GetAccountLayoutsTable()[normalizedKey]
	if storedSnapshot and type(storedSnapshot.bars) == "table" then
		return {
			key = normalizedKey,
			label = storedSnapshot.label or self:BuildSnapshotLabel(storedSnapshot.characterKey, storedSnapshot.specKey or requestedSpecKey),
			characterKey = tostring(storedSnapshot.characterKey or requestedCharacterKey or self:GetCurrentCharacterKey()),
			specKey = tostring(storedSnapshot.specKey or requestedSpecKey or normalizedKey),
			bars = util.DeepCopy(storedSnapshot.bars or {}),
			entries = util.DeepCopy(storedSnapshot.entries or {}),
		}
	end

	return nil
end

function Profile:GetLayoutSnapshots()
	local layouts = self:GetAccountLayoutsTable()
	local snapshots = {}
	local seen = {}

	self:ForEachStoredProfile(function(profile, characterKey, specKey)
		if type(profile) == "table" and type(profile.bars) == "table" then
			local snapshotKey = self:MakeSnapshotKey(characterKey, specKey)
			snapshots[#snapshots + 1] = {
				key = snapshotKey,
				label = self:BuildSnapshotLabel(characterKey, specKey),
				characterKey = tostring(characterKey),
				specKey = tostring(specKey),
				bars = util.DeepCopy(profile.bars or {}),
				entries = util.DeepCopy(profile.entries or {}),
			}
			seen[snapshotKey] = true
		end
	end)

	for snapshotKey, snapshot in pairs(layouts) do
		if not seen[snapshotKey] then
			local characterKey, parsedSpecKey = self:SplitSnapshotKey(snapshotKey)
			snapshots[#snapshots + 1] = {
				key = snapshotKey,
				label = snapshot.label or self:BuildSnapshotLabel(snapshot.characterKey or characterKey, snapshot.specKey or parsedSpecKey),
				characterKey = tostring(snapshot.characterKey or characterKey or self:GetCurrentCharacterKey()),
				specKey = tostring(snapshot.specKey or parsedSpecKey or snapshotKey),
				bars = util.DeepCopy(snapshot.bars or {}),
				entries = util.DeepCopy(snapshot.entries or {}),
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

	addon.profile.entries = {}
	for _, entry in ipairs(snapshot.entries or {}) do
		addon.profile.entries[#addon.profile.entries + 1] = NormalizeEntry(entry)
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
