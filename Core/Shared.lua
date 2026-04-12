local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar

addon.Constants = {
	MAX_BARS = 5,
	HIDDEN_CONTAINER_ID = "hidden",
	DEFAULT_BAR_ID = "bar1",
	FALLBACK_ITEM_ICON = 134400,
	GROWTH_LEFT = "left",
	GROWTH_CENTER = "center",
	GROWTH_RIGHT = "right",
}

addon.Defaults = {
	profile = {
		bars = {
			{
				id = addon.Constants.DEFAULT_BAR_ID,
				name = "Main",
				point = "CENTER",
				relativeTo = "UIParent",
				relativePoint = "CENTER",
				x = 0,
				y = -180,
				iconSize = 40,
				spacing = 6,
				growthDirection = addon.Constants.GROWTH_RIGHT,
				enabled = true,
			},
		},
		entries = {},
		options = {
			hidePassiveTrinkets = true,
			showTooltips = true,
			unifiedVisualStyleEnabled = true,
		},
	},
}

addon.Racials = {
	BloodElf = { 69179 },
	DarkIronDwarf = { 265221 },
	Dracthyr = { 357211, 358267, 368970 },
	Draenei = { 59542 },
	Dwarf = { 20594 },
	Earthen = { 436344 },
	Goblin = { 69070 },
	Gnome = { 20589 },
	HighmountainTauren = { 255654 },
	Human = { 59752 },
	KulTiran = { 287712 },
	LightforgedDraenei = { 255647 },
	MagharOrc = { 274738 },
	Mechagnome = { 312924 },
	Nightborne = { 260364 },
	NightElf = { 58984 },
	Orc = { 20572, 33697 },
	Pandaren = { 107079 },
	Scourge = { 7744 },
	Tauren = { 20549 },
	Troll = { 26297 },
	VoidElf = { 256948 },
	Vulpera = { 312411 },
	Worgen = { 68992 },
	ZandalariTroll = { 291944 },
}

addon.Util = addon.Util or {}
local util = addon.Util

util.tinsert = table.insert
util.tremove = table.remove
util.sort = table.sort
util.floor = math.floor
util.max = math.max
util.min = math.min

function util.DeepCopy(source)
	if type(source) ~= "table" then
		return source
	end
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = util.DeepCopy(value)
	end
	return copy
end

function util.ShallowCopy(source)
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

function util.NumberOrNil(value)
	if value == nil then
		return nil
	end
	if type(value) == "number" then
		return tonumber(tostring(value))
	end
	if type(value) == "string" then
		return tonumber(value)
	end
	return tonumber(tostring(value))
end

function util.MakeEntryID(kind, rawID)
	return kind .. ":" .. tostring(rawID)
end

function util.GetCurrentSpecKey()
	local specIndex = GetSpecialization and GetSpecialization()
	if specIndex and GetSpecializationInfo then
		local specID = GetSpecializationInfo(specIndex)
		if specID then
			return tostring(specID)
		end
	end
	return "0"
end

function util.GetCurrentSpecName()
	local specIndex = GetSpecialization and GetSpecialization()
	if specIndex and GetSpecializationInfo then
		local _, specName = GetSpecializationInfo(specIndex)
		if specName then
			return specName
		end
	end
	return "Unknown"
end

function util.GetCurrentClassName()
	local className = UnitClass("player")
	return className or "Unknown"
end

function util.GetCurrentSpecDisplayLabel()
	return string.format("%s - %s", util.GetCurrentClassName(), util.GetCurrentSpecName())
end

function util.GetSpecNameFromKey(specKey)
	local numericSpecID = tonumber(specKey)
	if numericSpecID and GetSpecializationInfoByID then
		local _, specName = GetSpecializationInfoByID(numericSpecID)
		if specName then
			return specName
		end
	end
	return tostring(specKey or "Unknown")
end

function util.GetSpecDisplayLabelForKey(specKey)
	return string.format("%s - %s", util.GetCurrentClassName(), util.GetSpecNameFromKey(specKey))
end

function util.GetSpellNameSafe(spellID)
	if not spellID then
		return nil
	end
	if type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then
		return C_Spell.GetSpellName(spellID)
	end
	if type(GetSpellInfo) == "function" then
		return GetSpellInfo(spellID)
	end
end

function util.GetSpellTextureSafe(spellID)
	if not spellID then
		return nil
	end
	if type(C_Spell) == "table" and type(C_Spell.GetSpellTexture) == "function" then
		return C_Spell.GetSpellTexture(spellID)
	end
	if type(GetSpellTexture) == "function" then
		return GetSpellTexture(spellID)
	end
end

function util.DoesSpellExistSafe(spellID)
	if not spellID then
		return false
	end
	if type(C_Spell) == "table" and type(C_Spell.DoesSpellExist) == "function" then
		return C_Spell.DoesSpellExist(spellID) == true
	end
	return util.GetSpellNameSafe(spellID) ~= nil
end

function util.IsValidSpellID(spellID)
	if not spellID then
		return false
	end

	local candidateSpellIDs = { spellID }
	local resolvedSpellID = util.ResolveSpellVariantID(spellID)
	if resolvedSpellID and resolvedSpellID ~= spellID then
		candidateSpellIDs[#candidateSpellIDs + 1] = resolvedSpellID
	end

	for _, candidateSpellID in ipairs(candidateSpellIDs) do
		if util.DoesSpellExistSafe(candidateSpellID) and util.GetSpellNameSafe(candidateSpellID) and util.GetSpellTextureSafe(candidateSpellID) then
			return true
		end
	end

	return false
end

function util.ResolveSpellVariantID(spellID)
	if not spellID then
		return nil
	end

	local resolvedSpellID = spellID

	if type(C_Spell) == "table" then
		if type(C_Spell.GetOverrideSpell) == "function" then
			local overrideSpellID = C_Spell.GetOverrideSpell(resolvedSpellID)
			if overrideSpellID then
				resolvedSpellID = overrideSpellID
			end
		end

		if type(C_Spell.GetBaseSpell) == "function" then
			local baseSpellID = C_Spell.GetBaseSpell(resolvedSpellID)
			if baseSpellID then
				resolvedSpellID = baseSpellID
			end
		end
	end

	return resolvedSpellID
end

function util.IsKnownPlayerSpell(spellID)
	if not spellID then
		return false
	end

	local candidateSpellIDs = { spellID }
	local resolvedSpellID = util.ResolveSpellVariantID(spellID)
	if resolvedSpellID and resolvedSpellID ~= spellID then
		candidateSpellIDs[#candidateSpellIDs + 1] = resolvedSpellID
	end

	for _, candidateSpellID in ipairs(candidateSpellIDs) do
		if type(C_Spell) == "table" and type(C_Spell.IsPlayerSpell) == "function" and C_Spell.IsPlayerSpell(candidateSpellID) then
			return true
		end
		if type(IsPlayerSpell) == "function" and IsPlayerSpell(candidateSpellID) then
			return true
		end
		if type(IsSpellKnownOrOverridesKnown) == "function" and IsSpellKnownOrOverridesKnown(candidateSpellID) then
			return true
		end
		if type(IsSpellKnown) == "function" and IsSpellKnown(candidateSpellID) then
			return true
		end
	end

	return false
end

function util.IsSpellUsableSafe(spellID)
	if not spellID then
		return false
	end

	local candidateSpellIDs = { spellID }
	local resolvedSpellID = util.ResolveSpellVariantID(spellID)
	if resolvedSpellID and resolvedSpellID ~= spellID then
		candidateSpellIDs[#candidateSpellIDs + 1] = resolvedSpellID
	end

	for _, candidateSpellID in ipairs(candidateSpellIDs) do
		if type(C_Spell) == "table" and type(C_Spell.IsSpellUsable) == "function" then
			local usable, noMana = C_Spell.IsSpellUsable(candidateSpellID)
			if usable ~= nil then
				return usable == true and noMana ~= true
			end
		end
		if type(IsUsableSpell) == "function" then
			local usable, noMana = IsUsableSpell(candidateSpellID)
			if usable ~= nil then
				return usable == true and noMana ~= true
			end
		end
	end

	return false
end

function util.GetInventoryItemName(unit, slotID)
	local itemID = GetInventoryItemID(unit, slotID)
	if itemID and C_Item and C_Item.GetItemNameByID then
		return C_Item.GetItemNameByID(itemID)
	end
	local itemLink = GetInventoryItemLink(unit, slotID)
	if itemLink then
		return GetItemInfo(itemLink)
	end
end

function util.GetInventoryItemSpellID(unit, slotID)
	local itemLink = GetInventoryItemLink(unit, slotID)
	if itemLink then
		local _, spellID = GetItemSpell(itemLink)
		return spellID
	end
end

function util.IsUsableTrinketSlot(slotID)
	return util.GetInventoryItemSpellID("player", slotID) ~= nil
end

function util.GetItemNameSafe(itemID)
	if not itemID then
		return nil
	end
	if C_Item and C_Item.GetItemNameByID then
		local itemName = C_Item.GetItemNameByID(itemID)
		if itemName then
			return itemName
		end
	end
	if GetItemInfo then
		local itemName = GetItemInfo(itemID)
		if itemName then
			return itemName
		end
	end
end

function util.GetItemLinkSafe(itemID)
	if not itemID then
		return nil
	end
	if C_Item and C_Item.GetItemInfo then
		local _, itemLink = C_Item.GetItemInfo(itemID)
		if itemLink then
			return itemLink
		end
	end
	if GetItemInfo then
		local _, itemLink = GetItemInfo(itemID)
		if itemLink then
			return itemLink
		end
	end
end

function util.GetItemIconSafe(itemID)
	if not itemID then
		return nil
	end
	if C_Item and C_Item.GetItemIconByID then
		local itemIcon = C_Item.GetItemIconByID(itemID)
		if itemIcon then
			return itemIcon
		end
	end
	if GetItemInfoInstant then
		local _, _, _, _, itemIcon = GetItemInfoInstant(itemID)
		if itemIcon then
			return itemIcon
		end
	end
end

function util.DoesItemExistSafe(itemID)
	if not itemID then
		return false
	end
	if C_Item and C_Item.DoesItemExistByID then
		return C_Item.DoesItemExistByID(itemID) == true
	end
	return util.GetItemNameSafe(itemID) ~= nil
end

function util.IsPlaceholderItemName(itemName)
	if not itemName or itemName == "" then
		return true
	end
	if RETRIEVING_ITEM_INFO and itemName == RETRIEVING_ITEM_INFO then
		return true
	end
	if RETRIEVING_DATA and itemName == RETRIEVING_DATA then
		return true
	end
	return false
end

function util.IsItemResolvable(itemID)
	if not itemID then
		return false
	end
	local itemName = util.GetItemNameSafe(itemID)
	local itemLink = util.GetItemLinkSafe(itemID)
	return util.DoesItemExistSafe(itemID) and not util.IsPlaceholderItemName(itemName) and itemLink ~= nil
end

function util.IsItemUsableSafe(itemID)
	if not itemID then
		return false
	end

	if type(C_Item) == "table" and type(C_Item.IsUsableItemByID) == "function" then
		local usable = C_Item.IsUsableItemByID(itemID)
		if usable ~= nil then
			return usable == true
		end
	end

	if type(IsUsableItem) == "function" then
		local itemLink = util.GetItemLinkSafe(itemID)
		local usable = itemLink and IsUsableItem(itemLink) or IsUsableItem(itemID)
		if usable ~= nil then
			return usable == true
		end
	end

	return false
end

function util.ValidateItemIDAsync(itemID, onSuccess, onFailure)
	if not itemID or not util.DoesItemExistSafe(itemID) then
		if onFailure then
			onFailure("invalid_item")
		end
		return false
	end

	if util.IsItemResolvable(itemID) then
		if onSuccess then
			onSuccess(itemID)
		end
		return true
	end

	if Item and Item.CreateFromItemID then
		local item = Item:CreateFromItemID(itemID)
		if item then
			item:ContinueOnItemLoad(function()
				if util.IsItemResolvable(itemID) then
					if onSuccess then
						onSuccess(itemID)
					end
				elseif onFailure then
					onFailure("unresolved_item")
				end
			end)
			return true
		end
	end

	if onFailure then
		onFailure("unresolved_item")
	end
	return false
end

function util.GetSpellCooldownState(spellID)
	if not spellID then
		return nil
	end
	if type(C_Spell) == "table" and type(C_Spell.GetSpellCooldown) == "function" then
		local candidateSpellIDs = { spellID }
		local resolvedSpellID = util.ResolveSpellVariantID(spellID)
		if resolvedSpellID and resolvedSpellID ~= spellID then
			candidateSpellIDs[#candidateSpellIDs + 1] = resolvedSpellID
		end

		for _, candidateSpellID in ipairs(candidateSpellIDs) do
			local info = C_Spell.GetSpellCooldown(candidateSpellID)
			if info then
				return {
					isEnabled = info.isEnabled == true,
					isActive = info.isActive == true,
					isOnGCD = info.isOnGCD == true,
				}
			end
		end
	end
end

function util.GetSpellCooldownDurationObject(spellID)
	if not spellID then
		return nil
	end
	if type(C_Spell) == "table" and type(C_Spell.GetSpellCooldownDuration) == "function" then
		local durationObject = C_Spell.GetSpellCooldownDuration(spellID)
		if durationObject then
			return durationObject
		end

		local resolvedSpellID = util.ResolveSpellVariantID(spellID)
		if resolvedSpellID and resolvedSpellID ~= spellID then
			return C_Spell.GetSpellCooldownDuration(resolvedSpellID)
		end
	end
end

function util.GetSpellChargesSafe(spellID)
	if not spellID then
		return nil
	end
	if type(C_Spell) == "table" and type(C_Spell.GetSpellCharges) == "function" then
		local chargeInfo = C_Spell.GetSpellCharges(spellID)
		if chargeInfo then
			return chargeInfo
		end

		local resolvedSpellID = util.ResolveSpellVariantID(spellID)
		if resolvedSpellID and resolvedSpellID ~= spellID then
			return C_Spell.GetSpellCharges(resolvedSpellID)
		end
	end
	if type(GetSpellCharges) == "function" then
		local currentCharges, maxCharges = GetSpellCharges(spellID)
		if currentCharges ~= nil then
			return { currentCharges = currentCharges, maxCharges = maxCharges }
		end
	end
end

function util.GetSpellChargeDurationObject(spellID)
	if not spellID then
		return nil
	end
	if type(C_Spell) == "table" and type(C_Spell.GetSpellChargeDuration) == "function" then
		local durationObject = C_Spell.GetSpellChargeDuration(spellID)
		if durationObject then
			return durationObject
		end

		local resolvedSpellID = util.ResolveSpellVariantID(spellID)
		if resolvedSpellID and resolvedSpellID ~= spellID then
			return C_Spell.GetSpellChargeDuration(resolvedSpellID)
		end
	end
end

function util.FormatTime(remaining)
	if not remaining then
		return ""
	end
	if remaining >= 60 then
		return string.format("%dm", util.floor((remaining + 5) / 60))
	elseif remaining >= 10 then
		return tostring(util.floor(remaining + 0.5))
	elseif remaining > 0 then
		return string.format("%.1f", remaining)
	end
	return ""
end
