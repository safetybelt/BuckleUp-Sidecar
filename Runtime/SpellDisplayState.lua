local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar
local util = addon.Util

local SpellDisplayState = {}
addon.SpellDisplayState = SpellDisplayState

local function AppendUniqueSpellID(targets, seen, spellID)
	local numericSpellID = util.NumberOrNil(spellID)
	if not numericSpellID or seen[numericSpellID] then
		return
	end

	seen[numericSpellID] = true
	targets[#targets + 1] = numericSpellID
end

function SpellDisplayState:GetChargeInfo(spellID)
	if not spellID or type(GetSpellCharges) ~= "function" then
		return nil
	end

	local candidateSpellIDs = {}
	local seenSpellIDs = {}
	AppendUniqueSpellID(candidateSpellIDs, seenSpellIDs, spellID)
	if type(C_Spell) == "table" then
		if type(C_Spell.GetOverrideSpell) == "function" then
			AppendUniqueSpellID(candidateSpellIDs, seenSpellIDs, C_Spell.GetOverrideSpell(spellID))
		end
		if type(C_Spell.GetBaseSpell) == "function" then
			AppendUniqueSpellID(candidateSpellIDs, seenSpellIDs, C_Spell.GetBaseSpell(spellID))
		end
	end

	for _, candidateSpellID in ipairs(candidateSpellIDs) do
		local currentCharges, maxCharges = GetSpellCharges(candidateSpellID)
		currentCharges = util.NumberOrNil(currentCharges)
		maxCharges = util.NumberOrNil(maxCharges)
		if currentCharges ~= nil and maxCharges ~= nil then
			return {
				spellID = candidateSpellID,
				currentCharges = currentCharges,
				maxCharges = maxCharges,
			}
		end
	end

	return nil
end

function SpellDisplayState:ShouldDesaturate(spellID, cooldownFrame, cooldownFrameCountsForDesaturation)
	local chargeInfo = self:GetChargeInfo(spellID)
	if chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
		return chargeInfo.currentCharges <= 0
	end

	if cooldownFrameCountsForDesaturation == false then
		return false
	end

	return cooldownFrame and cooldownFrame.IsShown and cooldownFrame:IsShown() or false
end
