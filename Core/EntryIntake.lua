local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar

local EntryIntake = {}
addon.EntryIntake = EntryIntake

function EntryIntake:RefreshAfterEntryChange()
	addon.Catalog:Rebuild()
	addon.Bars:RefreshRuntime()
	if addon.SettingsIntegration then
		addon.SettingsIntegration:RefreshPanel()
	end
end

function EntryIntake:AddSpell(spellID, options)
	options = options or {}
	if not addon.Util.IsValidSpellID(spellID) then
		if options.silent ~= true and addon.Print then
			addon.Print("That spell ID could not be validated. Try a real spell ID.")
		end
		if options.onComplete then
			options.onComplete(false, spellID)
		end
		return false
	end

	addon.Catalog:StoreCustomEntry({
		id = addon.Util.MakeEntryID("spell", spellID),
		kind = "spell",
		spellID = spellID,
	})
	self:RefreshAfterEntryChange()
	if options.onComplete then
		options.onComplete(true, spellID)
	end
	return true
end

function EntryIntake:AddItem(itemID, options)
	options = options or {}
	return addon.Util.ValidateItemIDAsync(itemID, function(validItemID)
		addon.Catalog:StoreCustomEntry({
			id = addon.Util.MakeEntryID("item", validItemID),
			kind = "item",
			itemID = validItemID,
		})
		self:RefreshAfterEntryChange()
		if options.onComplete then
			options.onComplete(true, validItemID)
		end
	end, function()
		if options.silent ~= true and addon.Print then
			addon.Print("That item ID could not be validated. Try a real item ID, item link, or bag drag.")
		end
		if options.onComplete then
			options.onComplete(false, itemID)
		end
	end)
end

function EntryIntake:AddByKind(kind, rawID, options)
	if kind == "spell" then
		return self:AddSpell(rawID, options)
	end

	if kind == "item" then
		return self:AddItem(rawID, options)
	end

	if options and options.onComplete then
		options.onComplete(false, rawID)
	end
	return false
end
