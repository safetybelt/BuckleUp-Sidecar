local addonName, addonTable = ...

local addon = addonTable or _G.BuckleUpSidecar or {}
_G.BuckleUpSidecar = addon

-- BuckleUpSidecar.lua intentionally stays small: bootstrap, refresh routing, and slash commands.
-- The feature logic lives in focused modules so the addon remains easy to evolve.

local function Print(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff7fd0ffBuckleUpSidecar:|r " .. tostring(message))
end

addon.Print = Print

local function EnsureCatalogEntry(entryID)
	local catalogEntry = addon.Catalog:GetEntry(entryID)
	if not catalogEntry then
		return nil
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

local function ResolveEntryID(rawID)
	if not rawID then
		return nil
	end
	if string.find(rawID, ":") then
		return rawID
	end
	local numeric = tonumber(rawID)
	if numeric then
		local spellEntryID = addon.Util.MakeEntryID("spell", numeric)
		local racialEntryID = addon.Util.MakeEntryID("racial", numeric)
		local itemEntryID = addon.Util.MakeEntryID("item", numeric)
		if addon.Catalog:GetEntry(spellEntryID) or addon.Profile:GetEntryByID(spellEntryID) then
			return spellEntryID
		end
		if addon.Catalog:GetEntry(racialEntryID) or addon.Profile:GetEntryByID(racialEntryID) then
			return racialEntryID
		end
		if addon.Catalog:GetEntry(itemEntryID) or addon.Profile:GetEntryByID(itemEntryID) then
			return itemEntryID
		end
		return spellEntryID
	end
	return rawID
end

local function RefreshAll()
	addon.Profile:RefreshProfile()
	addon.Catalog:Rebuild()
	addon.Bars:RefreshRuntime()
	if addon.CooldownViewerSkin then
		addon.CooldownViewerSkin:RefreshAll()
	end
	if addon.SettingsIntegration then
		addon.SettingsIntegration:RefreshPanel()
	end
end

local function RefreshCatalogAndRuntime()
	-- Catalog rebuilds are reserved for data-shape changes like gear/spec/spell updates.
	-- Cooldown ticks should not pay this cost.
	addon.Catalog:Rebuild()
	addon.Bars:RefreshRuntime()
	if addon.SettingsIntegration then
		addon.SettingsIntegration:RefreshPanel()
	end
end

local function RefreshRuntimeOnly()
	addon.Bars:RefreshRuntime()
end

local function SeedDefaultEntries()
	if #addon.Profile:GetConfiguredEntries() > 0 then
		return
	end
	for _, catalogEntry in ipairs(addon.Catalog:GetOrderedEntries()) do
		if catalogEntry.kind == "trinketSlot" or catalogEntry.kind == "racial" then
			addon.Profile:EnsureEntry({
				id = catalogEntry.id,
				kind = catalogEntry.kind,
				spellID = catalogEntry.spellID,
				itemID = catalogEntry.itemID,
				slotID = catalogEntry.slotID,
				containerID = addon.Constants.HIDDEN_CONTAINER_ID,
			})
		end
	end
	addon.Catalog:Rebuild()
end

local function DumpCatalog()
	for _, entry in ipairs(addon.Catalog:GetOrderedEntries()) do
		local rawID = entry.spellID or entry.itemID or entry.slotID or "?"
		Print(string.format("%s %s (%s)", entry.id, entry.name or "Unknown", tostring(rawID)))
	end
end

local function DumpProfile()
	Print(string.format("Spec %s: %d bars, %d configured entries", addon.profileKey or "?", #addon.Profile:GetBars(), #addon.Profile:GetConfiguredEntries()))
	for _, bar in ipairs(addon.Profile:GetBars()) do
		Print(string.format("Bar %s '%s' at (%d,%d), size %d, spacing %d", bar.id, bar.name, bar.x, bar.y, bar.iconSize, bar.spacing))
	end
	for _, entry in ipairs(addon.Profile:GetConfiguredEntries()) do
		Print(string.format("Entry %s -> %s #%d", entry.id, entry.containerID, entry.order))
	end
end

local function DumpLayouts()
	local snapshots = addon.Profile:GetLayoutSnapshots()
	Print(string.format("Found %d layout snapshots", #snapshots))
	for _, snapshot in ipairs(snapshots) do
		Print(string.format("%s -> %d bars", snapshot.label, #(snapshot.bars or {})))
	end
end

local function HandleSlash(message)
	local command, rest = message:match("^(%S*)%s*(.-)$")
	command = string.lower(command or "")

	if command == "" or command == "help" then
		Print("/bus catalog")
		Print("/bus profile")
		Print("/bus layouts")
		Print("/bus config")
		Print("/bus addspell <spellID>")
		Print("/bus additem <itemID>")
		Print("/bus remove <entryID|rawID>")
		Print("/bus move <entryID|rawID> <barID|hidden>")
		Print("/bus addbar <name>")
		return
	end

	if command == "catalog" then
		DumpCatalog()
		return
	end

	if command == "profile" then
		DumpProfile()
		return
	end

	if command == "layouts" then
		DumpLayouts()
		return
	end

	if command == "config" then
		if not _G.CooldownViewerSettings and C_AddOns and C_AddOns.LoadAddOn then
			C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
		end
		if _G.CooldownViewerSettings then
			_G.CooldownViewerSettings:ShowUIPanel()
			if addon.SettingsIntegration then
				addon.SettingsIntegration:EnsureUI()
				addon.SettingsIntegration:ShowSidecarPanel()
			end
		else
			Print("Cooldown Viewer settings are not available.")
		end
		return
	end

	if command == "addspell" then
		local spellID = tonumber(rest)
		if not spellID then
			Print("Usage: /bus addspell <spellID>")
			return
		end
		if not addon.Util.IsValidSpellID(spellID) then
			Print("That spell ID could not be validated.")
			return
		end
		addon.Profile:EnsureEntry({
			id = addon.Util.MakeEntryID("spell", spellID),
			kind = "spell",
			spellID = spellID,
			containerID = addon.Constants.HIDDEN_CONTAINER_ID,
		})
		RefreshAll()
		Print("Added spell:" .. tostring(spellID))
		return
	end

	if command == "additem" then
		local itemID = tonumber(rest)
		if not itemID then
			Print("Usage: /bus additem <itemID>")
			return
		end
		addon.Util.ValidateItemIDAsync(itemID, function(validItemID)
			addon.Profile:EnsureEntry({
				id = addon.Util.MakeEntryID("item", validItemID),
				kind = "item",
				itemID = validItemID,
				containerID = addon.Constants.HIDDEN_CONTAINER_ID,
			})
			RefreshAll()
			Print("Added item:" .. tostring(validItemID))
		end, function()
			Print("That item ID could not be validated.")
		end)
		return
	end

	if command == "move" then
		local source, target = rest:match("^(%S+)%s+(%S+)$")
		if not source or not target then
			Print("Usage: /bus move <entryID|rawID> <barID|hidden>")
			return
		end
		local entryID = ResolveEntryID(source)
		local entry = addon.Profile:GetEntryByID(entryID)
		if not entry then
			entry = EnsureCatalogEntry(entryID)
		end
		if not entry then
			Print("Missing entry: " .. tostring(source))
			return
		end
		local ok, reason = addon.Profile:SetEntryContainer(entry.id, target)
		if not ok then
			Print("Move failed: " .. tostring(reason))
			return
		end
		RefreshAll()
		Print("Moved " .. entry.id .. " to " .. target)
		return
	end

	if command == "remove" then
		local entryID = ResolveEntryID(rest)
		if not entryID then
			Print("Usage: /bus remove <entryID|rawID>")
			return
		end
		local entry = addon.Profile:GetEntryByID(entryID)
		if not entry then
			Print("Missing entry: " .. tostring(rest))
			return
		end
		local ok, reason = addon.Profile:RemoveEntry(entryID)
		if not ok then
			if reason == "protected_entry" then
				Print("That entry is part of the built-in sidecar setup and can't be removed.")
			else
				Print("Remove failed: " .. tostring(reason))
			end
			return
		end
		RefreshAll()
		Print("Removed " .. entryID)
		return
	end

	if command == "addbar" then
		local newBar, reason = addon.Profile:AddBar(rest ~= "" and rest or nil)
		if not newBar then
			Print("Add bar failed: " .. tostring(reason))
			return
		end
		RefreshAll()
		Print("Added bar " .. newBar.id .. " (" .. newBar.name .. ")")
		return
	end

	Print("Unknown command: " .. command)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("SPELL_UPDATE_CHARGES")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		local loadedAddon = select(1, ...)
		if loadedAddon == addonName and addon.CooldownViewerSkin then
			addon.CooldownViewerSkin:RefreshAll()
		end
		if loadedAddon == "Blizzard_CooldownViewer" and addon.SettingsIntegration then
			addon.SettingsIntegration:Initialize()
		end
		if loadedAddon == "Blizzard_CooldownViewer" and addon.CooldownViewerSkin then
			addon.CooldownViewerSkin:RefreshAll()
		end
		return
	end
	if event == "PLAYER_LOGIN" then
		RefreshAll()
		SeedDefaultEntries()
		addon.Profile:RecordLayoutSnapshot()
		addon.Bars:RefreshRuntime()
		if addon.SettingsIntegration then
			addon.SettingsIntegration:Initialize()
		end
		SLASH_BUCKLEUPSIDECAR1 = "/bus"
		SlashCmdList.BUCKLEUPSIDECAR = HandleSlash
		Print("Loaded. Use /bus help for commands.")
		return
	end
	if not addon.profile then
		return
	end
	if event == "PLAYER_SPECIALIZATION_CHANGED" then
		RefreshAll()
		addon.Profile:RecordLayoutSnapshot()
		if addon.SettingsIntegration then
			addon.SettingsIntegration:RefreshPanel()
		end
		return
	end
	if event == "PLAYER_EQUIPMENT_CHANGED" or event == "SPELLS_CHANGED" then
		RefreshCatalogAndRuntime()
		return
	end
	RefreshRuntimeOnly()
end)
