local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar
local util = addon.Util
local spellDisplayState = addon.SpellDisplayState

local Readiness = {}
addon.Readiness = Readiness

-- Item readiness still belongs here. Spell/racial runtime display state now lives in
-- Runtime/SpellDisplayState.lua so cooldown-driven visual policy has one explicit owner.
function Readiness:IsSpellReadyForUse(spellID)
	if not spellID then
		return false
	end

	if not util.IsKnownPlayerSpell(spellID) then
		return false
	end

	local chargeInfo = spellDisplayState and spellDisplayState:GetChargeInfo(spellID) or nil
	if chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
		return chargeInfo.currentCharges > 0
	end

	return true
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
