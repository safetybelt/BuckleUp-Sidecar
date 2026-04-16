local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar
local util = addon.Util
local constants = addon.Constants

local Catalog = {}
addon.Catalog = Catalog

local function AddCatalogEntry(catalog, entry)
	catalog[entry.id] = entry
end

local function NormalizeCustomEntry(entry)
	local normalized = util.ShallowCopy(entry or {})
	normalized.id = normalized.id or util.MakeEntryID(normalized.kind, normalized.spellID or normalized.itemID)
	normalized.kind = normalized.kind == "item" and "item" or "spell"
	normalized.source = "custom"
	normalized.isCustom = true
	normalized.isProtected = false
	return normalized
end

function Catalog:GetDatabaseRoot()
	BuckleUpSidecarDB = BuckleUpSidecarDB or {}
	BuckleUpSidecarDB.catalog = BuckleUpSidecarDB.catalog or {}
	BuckleUpSidecarDB.catalog.customEntries = BuckleUpSidecarDB.catalog.customEntries or {}
	BuckleUpSidecarDB.catalog.options = BuckleUpSidecarDB.catalog.options or {}
	if BuckleUpSidecarDB.catalog.options.showFullCatalog == nil then
		BuckleUpSidecarDB.catalog.options.showFullCatalog = false
	end
	return BuckleUpSidecarDB.catalog
end

function Catalog:GetCustomEntriesTable()
	return self:GetDatabaseRoot().customEntries
end

function Catalog:GetOptions()
	return self:GetDatabaseRoot().options
end

function Catalog:IsFullCatalogViewEnabled()
	return self:GetOptions().showFullCatalog == true
end

function Catalog:SetFullCatalogViewEnabled(enabled)
	self:GetOptions().showFullCatalog = enabled == true
	return true
end

function Catalog:StoreCustomEntry(entryData)
	local entry = NormalizeCustomEntry(entryData)
	self:GetCustomEntriesTable()[entry.id] = entry
	return entry
end

function Catalog:DeleteCustomEntry(entryID)
	local customEntries = self:GetCustomEntriesTable()
	local existing = customEntries[entryID]
	if not existing then
		return false, "missing_entry"
	end

	customEntries[entryID] = nil
	if addon.Profile and addon.Profile.ForEachStoredProfile then
		addon.Profile:ForEachStoredProfile(function(profile)
			local filteredEntries = {}
			for _, entry in ipairs(profile.entries or {}) do
				if entry.id ~= entryID then
					filteredEntries[#filteredEntries + 1] = entry
				end
			end
			profile.entries = filteredEntries
			if addon.Profile.NormalizeOrdersForEntries then
				addon.Profile:NormalizeOrdersForEntries(profile.entries)
			end
		end)
	end

	return true
end

function Catalog:BuildTrinketCatalog(catalog)
	for _, slotID in ipairs({ 13, 14 }) do
		local itemID = GetInventoryItemID("player", slotID)
		local name = util.GetInventoryItemName("player", slotID) or ("Trinket " .. tostring(slotID == 13 and 1 or 2))
		local icon = GetInventoryItemTexture("player", slotID) or constants.FALLBACK_ITEM_ICON
		local hasUseEffect = util.IsUsableTrinketSlot(slotID)
		if itemID or not addon.profile.options.hidePassiveTrinkets or hasUseEffect then
			AddCatalogEntry(catalog, {
				id = util.MakeEntryID("trinketSlot", slotID),
				kind = "trinketSlot",
				slotID = slotID,
				itemID = itemID,
				name = name,
				icon = icon,
				isAvailable = itemID ~= nil,
				hasUseEffect = hasUseEffect,
				source = "builtin",
				isCustom = false,
				isProtected = true,
			})
		end
	end
end

function Catalog:BuildRacialCatalog(catalog)
	local _, raceFile = UnitRace("player")
	local racialSpellIDs = addon.Racials[raceFile] or {}
	for _, spellID in ipairs(racialSpellIDs) do
		local name = util.GetSpellNameSafe(spellID)
		if util.IsValidSpellID(spellID) and name and util.IsKnownPlayerSpell(spellID) then
			AddCatalogEntry(catalog, {
				id = util.MakeEntryID("racial", spellID),
				kind = "racial",
				spellID = spellID,
				name = name,
				icon = util.GetSpellTextureSafe(spellID),
				isRelevant = true,
				isAvailable = true,
				source = "builtin",
				isCustom = false,
				isProtected = true,
			})
		end
	end
end

function Catalog:BuildCustomEntryCatalog(catalog)
	for entryID, storedEntry in pairs(self:GetCustomEntriesTable()) do
		local entry = NormalizeCustomEntry(storedEntry)
		if entry.kind == "spell" then
			local spellID = entry.spellID
			if util.IsValidSpellID(spellID) then
				local isRelevant = util.IsSpellRelevantToCurrentSpec(spellID)
				AddCatalogEntry(catalog, {
					id = entryID,
					kind = "spell",
					spellID = spellID,
					name = util.GetSpellNameSafe(spellID) or ("Spell " .. tostring(spellID)),
					icon = util.GetSpellTextureSafe(spellID) or constants.FALLBACK_ITEM_ICON,
					isRelevant = isRelevant,
					isAvailable = isRelevant and util.IsKnownPlayerSpell(spellID) or false,
					source = "custom",
					isCustom = true,
					isProtected = false,
				})
			end
		elseif entry.kind == "item" then
			local itemID = entry.itemID
			if itemID then
				AddCatalogEntry(catalog, {
					id = entryID,
					kind = "item",
					itemID = itemID,
					name = util.GetItemNameSafe(itemID) or ("Item " .. tostring(itemID)),
					icon = util.GetItemIconSafe(itemID) or constants.FALLBACK_ITEM_ICON,
					isRelevant = true,
					isAvailable = util.IsItemUsableSafe(itemID),
					source = "custom",
					isCustom = true,
					isProtected = false,
				})
			end
		end
	end
end

function Catalog:Rebuild()
	local catalog = {}
	self:BuildTrinketCatalog(catalog)
	self:BuildRacialCatalog(catalog)
	self:BuildCustomEntryCatalog(catalog)
	addon.catalog = catalog
	return catalog
end

function Catalog:Get()
	return addon.catalog or self:Rebuild()
end

function Catalog:GetEntry(entryID)
	local catalog = self:Get()
	return catalog and catalog[entryID]
end

function Catalog:ShouldShowInOrganizer(entry, configuredEntry)
	if not entry then
		return false
	end

	if self:IsFullCatalogViewEnabled() then
		return true
	end

	if entry.kind ~= "spell" then
		return true
	end

	if configuredEntry and configuredEntry.containerID ~= constants.HIDDEN_CONTAINER_ID then
		return true
	end

	return entry.isRelevant == true
end

function Catalog:ShouldShowOnRuntimeBar(entry, catalogEntry)
	if not entry or not catalogEntry then
		return false
	end

	if entry.kind == "trinketSlot" then
		return catalogEntry.itemID ~= nil and catalogEntry.hasUseEffect == true
	end

	if entry.kind == "spell" then
		return catalogEntry.isRelevant == true
	end

	return true
end

function Catalog:GetOrderedEntries()
	local entries = {}
	for _, entry in pairs(self:Get()) do
		entries[#entries + 1] = entry
	end
	table.sort(entries, function(left, right)
		if left.kind == right.kind then
			return (left.name or left.id) < (right.name or right.id)
		end
		return left.kind < right.kind
	end)
	return entries
end
