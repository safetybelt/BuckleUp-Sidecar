local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar
local util = addon.Util
local constants = addon.Constants

local Catalog = {}
addon.Catalog = Catalog

local function AddCatalogEntry(catalog, entry)
	catalog[entry.id] = entry
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
				isAvailable = true,
			})
		end
	end
end

function Catalog:BuildPersistedEntryCatalog(catalog)
	for _, entry in ipairs(addon.Profile:GetConfiguredEntries()) do
		if entry.kind == "spell" or entry.kind == "racial" then
			local spellID = entry.spellID
			if util.IsValidSpellID(spellID) then
				AddCatalogEntry(catalog, {
					id = entry.id,
					kind = entry.kind,
					spellID = spellID,
					name = util.GetSpellNameSafe(spellID) or ("Spell " .. tostring(spellID)),
					icon = util.GetSpellTextureSafe(spellID),
					isAvailable = util.IsKnownPlayerSpell(spellID),
				})
			end
		elseif entry.kind == "item" then
			local itemID = entry.itemID
			if util.IsItemResolvable(itemID) then
				local itemName = util.GetItemNameSafe(itemID) or ("Item " .. tostring(itemID))
				local itemIcon = util.GetItemIconSafe(itemID) or constants.FALLBACK_ITEM_ICON
				AddCatalogEntry(catalog, {
					id = entry.id,
					kind = "item",
					itemID = itemID,
					name = itemName,
					icon = itemIcon,
					isAvailable = itemName ~= nil,
				})
			end
		elseif entry.kind == "trinketSlot" then
			local slotID = entry.slotID
			AddCatalogEntry(catalog, {
				id = entry.id,
				kind = "trinketSlot",
				slotID = slotID,
				itemID = GetInventoryItemID("player", slotID),
				name = util.GetInventoryItemName("player", slotID) or ("Trinket " .. tostring(slotID == 13 and 1 or 2)),
				icon = GetInventoryItemTexture("player", slotID) or constants.FALLBACK_ITEM_ICON,
				isAvailable = GetInventoryItemID("player", slotID) ~= nil,
				hasUseEffect = util.IsUsableTrinketSlot(slotID),
			})
		end
	end
end

function Catalog:Rebuild()
	local catalog = {}
	self:BuildTrinketCatalog(catalog)
	self:BuildRacialCatalog(catalog)
	self:BuildPersistedEntryCatalog(catalog)
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
