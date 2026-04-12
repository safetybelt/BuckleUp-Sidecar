local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar
local util = addon.Util

local Readiness = {}
addon.Readiness = Readiness

function Readiness:IsSpellReadyForUse(spellID)
	if not spellID then
		return false
	end

	if not util.IsSpellUsableSafe(spellID) then
		return false
	end

	local chargeInfo = util.GetSpellChargesSafe(spellID)
	if chargeInfo and chargeInfo.currentCharges ~= nil and chargeInfo.maxCharges ~= nil then
		-- Some spells are charge-backed even when the player currently only has one
		-- charge available. In those cases readiness still follows currentCharges.
		return (chargeInfo.currentCharges or 0) > 0
	end

	local cooldownState = util.GetSpellCooldownState(spellID)
	if cooldownState then
		if cooldownState.isOnGCD then
			return true
		end
		if cooldownState.isEnabled == false then
			return false
		end
	end

	local durationObject = util.GetSpellCooldownDurationObject(spellID)
	return durationObject == nil
end

function Readiness:IsItemReadyForUse(itemID, slotID)
	if slotID then
		local startTime, duration, enabled = GetInventoryItemCooldown("player", slotID)
		startTime = util.NumberOrNil(startTime) or 0
		duration = util.NumberOrNil(duration) or 0
		enabled = enabled ~= false and enabled ~= 0
		if enabled and startTime > 0 and duration > 0 then
			return false
		end

		local equippedItemID = GetInventoryItemID("player", slotID)
		return equippedItemID ~= nil and util.IsItemUsableSafe(equippedItemID)
	end

	if not itemID or not util.IsItemUsableSafe(itemID) then
		return false
	end

	if type(C_Item) == "table" and type(C_Item.GetItemCooldownByID) == "function" then
		local startTime, duration, enabled = C_Item.GetItemCooldownByID(itemID)
		startTime = util.NumberOrNil(startTime) or 0
		duration = util.NumberOrNil(duration) or 0
		enabled = enabled ~= false and enabled ~= 0
		if enabled and startTime > 0 and duration > 0 then
			return false
		end
	end

	return true
end
