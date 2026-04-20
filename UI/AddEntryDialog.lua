local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar

local AddEntryDialog = {}
addon.AddEntryDialog = AddEntryDialog

local modifiedItemHookInstalled = false
local addEntryDialogInitialized = false

local function ParseManualEntryInput(rawText)
	local trimmedText = strtrim(rawText or "")
	if trimmedText == "" then
		return nil, "empty"
	end

	local explicitSpellID = tonumber(trimmedText:match("^[Ss][Pp][Ee][Ll][Ll]%s*[:#]%s*(%d+)$"))
	if explicitSpellID then
		return "spell", explicitSpellID
	end

	local explicitItemID = tonumber(trimmedText:match("^[Ii][Tt][Ee][Mm]%s*[:#]%s*(%d+)$"))
	if explicitItemID then
		return "item", explicitItemID
	end

	local linkedSpellID = tonumber(trimmedText:match("spell:(%d+)"))
	if linkedSpellID then
		return "spell", linkedSpellID
	end

	local linkedItemID = tonumber(trimmedText:match("item:(%d+)"))
	if linkedItemID then
		return "item", linkedItemID
	end

	local numericID = tonumber(trimmedText)
	if not numericID then
		return nil, "invalid"
	end

	local isValidSpell = addon.Util.IsValidSpellID(numericID)
	local isExistingItem = addon.Util.DoesItemExistSafe and addon.Util.DoesItemExistSafe(numericID)
	if isValidSpell and isExistingItem then
		local isKnownPlayerSpell = addon.Util.IsKnownPlayerSpell and addon.Util.IsKnownPlayerSpell(numericID)
		local isRelevantSpell = addon.Util.IsSpellRelevantToCurrentSpec and addon.Util.IsSpellRelevantToCurrentSpec(numericID)
		if isKnownPlayerSpell or isRelevantSpell then
			return "spell", numericID
		end

		return "item", numericID
	end
	if isValidSpell then
		return "spell", numericID
	end

	return "item", numericID
end

local function EnsureDialogHooks()
	if modifiedItemHookInstalled or type(hooksecurefunc) ~= "function" then
		return
	end

	modifiedItemHookInstalled = true
	hooksecurefunc("HandleModifiedItemClick", function(link)
		if not IsModifiedClick("CHATLINK") or not link then
			return
		end

		local popup = StaticPopup_FindVisible("BUCKLEUPSIDECAR_ADD_ENTRY")
		if not popup then
			return
		end

		local editBox = popup.editBox or popup.EditBox
		if editBox and editBox:HasFocus() then
			editBox:SetText(link)
			editBox:SetFocus()
			editBox:HighlightText()
		end
	end)
end

local function EnsureDialog()
	if addEntryDialogInitialized then
		return
	end

	addEntryDialogInitialized = true
	StaticPopupDialogs["BUCKLEUPSIDECAR_ADD_ENTRY"] = {
		text = "Add Entry\nEnter spell/item ID, shift-click a link, or use spell:123 / item:123",
		button1 = ADD,
		button2 = CANCEL,
		hasEditBox = true,
		enterClicksFirstButton = true,
		whileDead = true,
		hideOnEscape = true,
		timeout = 0,
		preferredIndex = 3,
		OnShow = function(self)
			local editBox = self.editBox or self.EditBox
			if not editBox then
				return
			end

			if not editBox.BuckleUpSidecarLinkHooks then
				editBox.BuckleUpSidecarLinkHooks = true
				editBox:HookScript("OnEditFocusGained", function(focusedBox)
					focusedBox.BuckleUpPreviousActiveChatEditBox = _G.ACTIVE_CHAT_EDIT_BOX
					focusedBox.BuckleUpPreviousLastActiveChatEditBox = _G.LAST_ACTIVE_CHAT_EDIT_BOX
					_G.ACTIVE_CHAT_EDIT_BOX = focusedBox
					_G.LAST_ACTIVE_CHAT_EDIT_BOX = focusedBox
				end)
				editBox:HookScript("OnEditFocusLost", function(focusedBox)
					if _G.ACTIVE_CHAT_EDIT_BOX == focusedBox then
						_G.ACTIVE_CHAT_EDIT_BOX = focusedBox.BuckleUpPreviousActiveChatEditBox
					end
					if _G.LAST_ACTIVE_CHAT_EDIT_BOX == focusedBox then
						_G.LAST_ACTIVE_CHAT_EDIT_BOX = focusedBox.BuckleUpPreviousLastActiveChatEditBox
					end
				end)
			end

			editBox:SetText("")
			editBox:SetFocus()
			editBox:HighlightText()
		end,
		OnHide = function(self)
			local editBox = self.editBox or self.EditBox
			if not editBox then
				return
			end

			if _G.ACTIVE_CHAT_EDIT_BOX == editBox then
				_G.ACTIVE_CHAT_EDIT_BOX = editBox.BuckleUpPreviousActiveChatEditBox
			end
			if _G.LAST_ACTIVE_CHAT_EDIT_BOX == editBox then
				_G.LAST_ACTIVE_CHAT_EDIT_BOX = editBox.BuckleUpPreviousLastActiveChatEditBox
			end
		end,
		OnAccept = function(self)
			local editBox = self.editBox or self.EditBox
			local rawText = (editBox and editBox:GetText()) or ""
			local kind, rawIDOrReason = ParseManualEntryInput(rawText)
			if not kind then
				if addon.Print then
					if rawIDOrReason == "ambiguous" then
						addon.Print("That ID could be either a spell or an item. Use spell:<id> or item:<id>.")
					else
						addon.Print("Enter a spell ID, item ID, spell link, or item link.")
					end
				end
				return
			end

			addon.EntryIntake:AddByKind(kind, rawIDOrReason)
		end,
		EditBoxOnEnterPressed = function(self)
			local parent = self:GetParent()
			if parent and parent.button1 and parent.button1:IsEnabled() then
				parent.button1:Click()
			end
		end,
		EditBoxOnEscapePressed = function(self)
			if type(StaticPopup_StandardEditBoxOnEscapePressed) == "function" then
				StaticPopup_StandardEditBoxOnEscapePressed(self)
				return
			end

			local parent = self:GetParent()
			if parent then
				parent:Hide()
			end
		end,
	}
end

function AddEntryDialog:Open()
	EnsureDialogHooks()
	EnsureDialog()
	StaticPopup_Show("BUCKLEUPSIDECAR_ADD_ENTRY")
end
