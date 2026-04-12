local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar

local Skin = {}
addon.CooldownViewerSkin = Skin

local ICON_TEX_COORD = {
	left = 0.14,
	right = 0.86,
	top = 0.14,
	bottom = 0.86,
}

local BORDER_COLOR = { r = 0.10, g = 0.10, b = 0.10, a = 0.96 }
local AURA_BORDER_COLOR = { r = 0.95, g = 0.82, b = 0.25, a = 0.96 }
local PROC_BORDER_COLOR = { r = 1.00, g = 0.91, b = 0.38, a = 1.00 }
local FLASH_BORDER_COLOR = { r = 0.95, g = 0.82, b = 0.25, a = 1.00 }

local SQUARE_SWIPE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_VIEWER_SWIPE_TEXTURE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local DEFAULT_VIEWER_OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local DEFAULT_VIEWER_MASK_ATLAS = "UI-HUD-CoolDownManager-Mask"

local COOLDOWN_VIEWER_FRAME_NAMES = {
	"EssentialCooldownViewer",
	"UtilityCooldownViewer",
	"BuffIconCooldownViewer",
	"BuffBarCooldownViewer",
}

local function SafeCall(methodOwner, methodName, ...)
	if not methodOwner then
		return false
	end

	local method = methodOwner[methodName]
	if type(method) ~= "function" then
		return false
	end

	return pcall(method, methodOwner, ...)
end

local function ApplyTexCoord(texture)
	if not texture or type(texture.SetTexCoord) ~= "function" then
		return
	end

	texture:SetTexCoord(
		ICON_TEX_COORD.left,
		ICON_TEX_COORD.right,
		ICON_TEX_COORD.top,
		ICON_TEX_COORD.bottom
	)
end

local function ResetTexCoord(texture)
	if not texture or type(texture.SetTexCoord) ~= "function" then
		return
	end

	texture:SetTexCoord(0, 1, 0, 1)
end

local function AddRegionTargets(frame, targets)
	if not frame or type(frame.GetRegions) ~= "function" then
		return
	end

	for _, region in ipairs({ frame:GetRegions() }) do
		targets[#targets + 1] = region
	end
end

local function EnsureBorderFrame(styleData)
	if not styleData or styleData.borderFrame then
		return styleData and styleData.borderFrame or nil
	end

	local parent = styleData.iconOwner or styleData.ownerFrame
	if not parent then
		return nil
	end

	local borderFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	borderFrame:SetPoint("TOPLEFT", styleData.iconTexture, "TOPLEFT", -2, 2)
	borderFrame:SetPoint("BOTTOMRIGHT", styleData.iconTexture, "BOTTOMRIGHT", 2, -2)
	borderFrame:SetFrameStrata(parent:GetFrameStrata())
	borderFrame:SetFrameLevel(math.max(parent:GetFrameLevel() + 1, 1))
	borderFrame:SetBackdrop({
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 2,
		insets = { left = 0, right = 0, top = 0, bottom = 0 },
	})
	borderFrame:SetBackdropColor(0, 0, 0, 0)
	borderFrame:SetBackdropBorderColor(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, BORDER_COLOR.a)
	borderFrame:Hide()

	styleData.borderFrame = borderFrame
	return borderFrame
end

local function EnsureFlashFrame(styleData)
	if not styleData or styleData.flashFrame then
		return styleData and styleData.flashFrame or nil
	end

	local parent = styleData.iconOwner or styleData.ownerFrame
	if not parent then
		return nil
	end

	local flashFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	flashFrame:SetPoint("TOPLEFT", styleData.iconTexture, "TOPLEFT", -3, 3)
	flashFrame:SetPoint("BOTTOMRIGHT", styleData.iconTexture, "BOTTOMRIGHT", 3, -3)
	flashFrame:SetFrameStrata(parent:GetFrameStrata())
	flashFrame:SetFrameLevel(math.max(parent:GetFrameLevel() + 4, 1))
	flashFrame:SetBackdrop({
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 3,
		insets = { left = 0, right = 0, top = 0, bottom = 0 },
	})
	flashFrame:SetBackdropColor(0, 0, 0, 0)
	flashFrame:SetBackdropBorderColor(FLASH_BORDER_COLOR.r, FLASH_BORDER_COLOR.g, FLASH_BORDER_COLOR.b, FLASH_BORDER_COLOR.a)
	flashFrame:SetAlpha(0)
	flashFrame:Hide()

	local animationGroup = flashFrame:CreateAnimationGroup()

	local fadeIn = animationGroup:CreateAnimation("Alpha")
	fadeIn:SetOrder(1)
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.08)

	local fadeOut = animationGroup:CreateAnimation("Alpha")
	fadeOut:SetOrder(2)
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(0.45)
	fadeOut:SetStartDelay(0.02)

	animationGroup:SetScript("OnPlay", function()
		flashFrame:Show()
		flashFrame:SetAlpha(0)
	end)
	animationGroup:SetScript("OnFinished", function()
		flashFrame:SetAlpha(0)
		flashFrame:Hide()
	end)
	animationGroup:SetScript("OnStop", function()
		flashFrame:SetAlpha(0)
		flashFrame:Hide()
	end)

	styleData.flashFrame = flashFrame
	styleData.flashAnimation = animationGroup
	styleData.flashFadeIn = fadeIn
	styleData.flashFadeOut = fadeOut
	return flashFrame
end

local function PlayBorderFlash(styleData, startDelay)
	if not styleData then
		return
	end

	EnsureFlashFrame(styleData)
	if not styleData.flashAnimation then
		return
	end

	if styleData.flashFadeIn and type(styleData.flashFadeIn.SetStartDelay) == "function" then
		styleData.flashFadeIn:SetStartDelay(startDelay or 0)
	end
	if styleData.flashFadeOut and type(styleData.flashFadeOut.SetStartDelay) == "function" then
		styleData.flashFadeOut:SetStartDelay((startDelay or 0) + 0.10)
	end

	if styleData.flashAnimation:IsPlaying() then
		styleData.flashAnimation:Stop()
	end
	styleData.flashAnimation:Play()
end

local function SetBorderColor(frame, colorInfo)
	if not frame or not colorInfo or type(frame.SetBackdropBorderColor) ~= "function" then
		return
	end

	frame:SetBackdropBorderColor(colorInfo.r, colorInfo.g, colorInfo.b, colorInfo.a)
end

local function ResolveViewerStyleState(itemFrame)
	local isAuraActive = itemFrame and itemFrame.wasSetFromAura == true
	local isProcActive = false

	if itemFrame and itemFrame.SpellActivationAlert and itemFrame.SpellActivationAlert.IsShown and itemFrame.SpellActivationAlert:IsShown() then
		isProcActive = true
	end

	local spellID = itemFrame and itemFrame.GetSpellID and itemFrame:GetSpellID() or nil
	if spellID and type(C_SpellActivationOverlay) == "table" and type(C_SpellActivationOverlay.IsSpellOverlayed) == "function" then
		isProcActive = C_SpellActivationOverlay.IsSpellOverlayed(spellID) == true or isProcActive
	end

	return {
		isAuraActive = isAuraActive,
		isProcActive = isProcActive,
	}
end

local function SuppressProcAlertArt(itemFrame)
	local alertFrame = itemFrame and itemFrame.SpellActivationAlert
	if not alertFrame then
		return
	end

	if alertFrame.ProcStartAnim and type(alertFrame.ProcStartAnim.Stop) == "function" then
		alertFrame.ProcStartAnim:Stop()
	end
	if alertFrame.ProcLoop and type(alertFrame.ProcLoop.Stop) == "function" then
		alertFrame.ProcLoop:Stop()
	end
	if alertFrame.ProcStartFlipbook and type(alertFrame.ProcStartFlipbook.Hide) == "function" then
		alertFrame.ProcStartFlipbook:Hide()
	end
	if alertFrame.ProcLoopFlipbook and type(alertFrame.ProcLoopFlipbook.Hide) == "function" then
		alertFrame.ProcLoopFlipbook:Hide()
	end
	if alertFrame.ProcAltGlow and type(alertFrame.ProcAltGlow.Hide) == "function" then
		alertFrame.ProcAltGlow:Hide()
	end
	alertFrame:SetAlpha(0)
	if type(alertFrame.Hide) == "function" then
		alertFrame:Hide()
	end
end

local function RestoreProcAlertArt(itemFrame)
	local alertFrame = itemFrame and itemFrame.SpellActivationAlert
	if not alertFrame then
		return
	end

	alertFrame:SetAlpha(1)

	Skin.procAlertRestoreInProgress = Skin.procAlertRestoreInProgress or {}
	if Skin.procAlertRestoreInProgress[itemFrame] then
		return
	end

	local hasAlert = ActionButtonSpellAlertManager
		and type(ActionButtonSpellAlertManager.HasAlert) == "function"
		and ActionButtonSpellAlertManager:HasAlert(itemFrame)

	if not hasAlert then
		return
	end

	-- We suppress Blizzard's proc art by stopping/hiding its alert frame. When the
	-- unified style is turned off mid-session, the safest restoration is to hand the
	-- frame back to Blizzard by replaying its own hide/show path once.
	Skin.procAlertRestoreInProgress[itemFrame] = true
	if type(ActionButtonSpellAlertManager.HideAlert) == "function" then
		ActionButtonSpellAlertManager:HideAlert(itemFrame)
	end
	if type(ActionButtonSpellAlertManager.ShowAlert) == "function" then
		ActionButtonSpellAlertManager:ShowAlert(itemFrame)
	end
	Skin.procAlertRestoreInProgress[itemFrame] = nil
end

function Skin:GetRuntimeState(entry, visual)
	local state = {
		isAuraActive = false,
		isProcActive = false,
	}

	if not entry or not visual then
		return state
	end

	if (entry.kind == "spell" or entry.kind == "racial") and visual.spellID then
		-- Sidecar runtime entries do not have Blizzard's aura-owned viewer context.
		-- Treat proc overlays as the only runtime "active" visual for now so a
		-- normal cooldown does not incorrectly read like an aura/proc highlight.
		if type(C_SpellActivationOverlay) == "table" and type(C_SpellActivationOverlay.IsSpellOverlayed) == "function" then
			state.isProcActive = C_SpellActivationOverlay.IsSpellOverlayed(visual.spellID) == true
		end
	end

	return state
end

function Skin:IsEnabled()
	return addon.Profile and addon.Profile.IsUnifiedVisualStyleEnabled and addon.Profile:IsUnifiedVisualStyleEnabled()
end

function Skin:BuildRuntimeButtonData(button)
	if button.BUSkinData then
		return button.BUSkinData
	end

	if not button or not button.Icon then
		return nil
	end

	local styleData = {
		ownerFrame = button,
		iconOwner = button,
		iconTexture = button.Icon,
		cooldownFrame = button.Cooldown,
		maskRegions = button.Mask and { button.Mask } or {},
		overlayRegions = button.Overlay and { button.Overlay } or {},
		swipeTextures = {},
		defaultSwipeTexture = DEFAULT_VIEWER_SWIPE_TEXTURE,
		defaultOverlayAtlas = DEFAULT_VIEWER_OVERLAY_ATLAS,
		defaultMaskAtlas = DEFAULT_VIEWER_MASK_ATLAS,
	}

	button.BUSkinData = styleData
	return styleData
end

local function ResolveCooldownViewerIconParts(itemFrame)
	if not itemFrame then
		return nil, nil
	end

	if itemFrame.Icon and type(itemFrame.Icon.GetObjectType) == "function" and itemFrame.Icon:GetObjectType() == "Texture" then
		return itemFrame.Icon, itemFrame
	end

	if itemFrame.Icon and itemFrame.Icon.Icon and type(itemFrame.Icon.Icon.GetObjectType) == "function" and itemFrame.Icon.Icon:GetObjectType() == "Texture" then
		return itemFrame.Icon.Icon, itemFrame.Icon
	end

	return nil, nil
end

local function CollectKnownViewerRegions(styleData)
	if not styleData or not styleData.cooldownFrame then
		return
	end

	local scanTargets = {}
	AddRegionTargets(styleData.ownerFrame, scanTargets)
	if styleData.iconOwner ~= styleData.ownerFrame then
		AddRegionTargets(styleData.iconOwner, scanTargets)
	end

	for _, region in ipairs(scanTargets) do
		if region and type(region.GetObjectType) == "function" then
			local objectType = region:GetObjectType()
			if objectType == "MaskTexture" then
				styleData.maskRegions[#styleData.maskRegions + 1] = region
			elseif objectType == "Texture" and type(region.GetAtlas) == "function" then
				local atlas = region:GetAtlas()
				if atlas == DEFAULT_VIEWER_OVERLAY_ATLAS then
					styleData.overlayRegions[#styleData.overlayRegions + 1] = region
				end
			end
		end
	end

	for _, region in ipairs({ styleData.cooldownFrame:GetRegions() }) do
		if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "Texture" then
			local texturePath = type(region.GetTexture) == "function" and region:GetTexture() or nil
			if texturePath == DEFAULT_VIEWER_SWIPE_TEXTURE then
				styleData.swipeTextures[#styleData.swipeTextures + 1] = region
			end
		end
	end
end

local function DeduplicateRegions(regions)
	local unique = {}
	local seen = {}
	for _, region in ipairs(regions or {}) do
		if region and not seen[region] then
			seen[region] = true
			unique[#unique + 1] = region
		end
	end
	return unique
end

function Skin:BuildCooldownViewerData(itemFrame)
	if itemFrame.BUSkinData then
		return itemFrame.BUSkinData
	end

	local iconTexture, iconOwner = ResolveCooldownViewerIconParts(itemFrame)
	if not iconTexture then
		return nil
	end

	-- Blizzard's cooldown viewer templates consistently expose Icon and Cooldown
	-- directly, but they do not expose stable named handles for every mask/overlay/
	-- swipe region we need to restyle. We therefore prefer the known template shape
	-- first and then do a best-effort region scan for the remaining presentation
	-- assets. This is intentionally a narrow interop shim, not a broad frame-skinning
	-- framework, and each discovered region is optional.
	local styleData = {
		ownerFrame = itemFrame,
		iconOwner = iconOwner,
		iconTexture = iconTexture,
		cooldownFrame = itemFrame.Cooldown,
		maskRegions = {},
		overlayRegions = {},
		swipeTextures = {},
		defaultSwipeTexture = DEFAULT_VIEWER_SWIPE_TEXTURE,
		defaultOverlayAtlas = DEFAULT_VIEWER_OVERLAY_ATLAS,
		defaultMaskAtlas = DEFAULT_VIEWER_MASK_ATLAS,
	}

	if styleData.cooldownFrame and type(styleData.cooldownFrame.GetRegions) == "function" then
		CollectKnownViewerRegions(styleData)
		styleData.maskRegions = DeduplicateRegions(styleData.maskRegions)
		styleData.overlayRegions = DeduplicateRegions(styleData.overlayRegions)
		styleData.swipeTextures = DeduplicateRegions(styleData.swipeTextures)
	end

	itemFrame.BUSkinData = styleData
	return styleData
end

function Skin:InstallRuntimeFlashHooks(button)
	if not button or button.BUSkinFlashHooksInstalled then
		return
	end

	local styleData = self:BuildRuntimeButtonData(button)
	EnsureFlashFrame(styleData)

	if button.Cooldown and type(button.Cooldown.HookScript) == "function" then
		button.Cooldown:HookScript("OnCooldownDone", function()
			PlayBorderFlash(styleData, 0)
		end)
	end

	button.BUSkinFlashHooksInstalled = true
end

function Skin:InstallViewerFlashHooks(itemFrame)
	local styleData = self:BuildCooldownViewerData(itemFrame)
	if not itemFrame or not styleData or styleData.viewerFlashHooksInstalled then
		return
	end

	local cooldownFlashFrame = itemFrame.CooldownFlash
	if cooldownFlashFrame and cooldownFlashFrame.FlashAnim then
		EnsureFlashFrame(styleData)

		hooksecurefunc(cooldownFlashFrame.FlashAnim, "Play", function()
			local startDelay = 0
			if cooldownFlashFrame.FlashAnim.PlayAnim and type(cooldownFlashFrame.FlashAnim.PlayAnim.GetStartDelay) == "function" then
				startDelay = cooldownFlashFrame.FlashAnim.PlayAnim:GetStartDelay() or 0
			end
			PlayBorderFlash(styleData, startDelay)
		end)

		hooksecurefunc(cooldownFlashFrame.FlashAnim, "Stop", function()
			if styleData.flashAnimation and styleData.flashAnimation:IsPlaying() then
				styleData.flashAnimation:Stop()
			end
		end)
	end

	styleData.viewerFlashHooksInstalled = true
end

function Skin:ApplyStyleData(styleData, styleState)
	if not styleData or not styleData.iconTexture then
		return
	end

	styleState = styleState or {}

	local borderFrame = EnsureBorderFrame(styleData)
	EnsureFlashFrame(styleData)

	ApplyTexCoord(styleData.iconTexture)

	if styleData.cooldownFrame and type(styleData.cooldownFrame.SetUseCircularEdge) == "function" then
		styleData.cooldownFrame:SetUseCircularEdge(false)
	end
	if styleData.cooldownFrame and type(styleData.cooldownFrame.SetSwipeTexture) == "function" then
		styleData.cooldownFrame:SetSwipeTexture(SQUARE_SWIPE_TEXTURE, 1, 1, 1, 1)
	end
	if styleData.cooldownFrame and type(styleData.cooldownFrame.SetDrawBling) == "function" then
		styleData.cooldownFrame:SetDrawBling(false)
	end

	for _, maskRegion in ipairs(styleData.maskRegions or {}) do
		SafeCall(styleData.iconTexture, "RemoveMaskTexture", maskRegion)
		if type(maskRegion.Hide) == "function" then
			maskRegion:Hide()
		end
	end

	for _, overlayRegion in ipairs(styleData.overlayRegions or {}) do
		if type(overlayRegion.Hide) == "function" then
			overlayRegion:Hide()
		end
	end

	for _, swipeTexture in ipairs(styleData.swipeTextures or {}) do
		ApplyTexCoord(swipeTexture)
	end

	local borderColor = BORDER_COLOR
	if styleState.isAuraActive then
		borderColor = AURA_BORDER_COLOR
	end
	if styleState.isProcActive then
		borderColor = PROC_BORDER_COLOR
	end

	if borderFrame then
		SetBorderColor(borderFrame, borderColor)
		borderFrame:Show()
	end

	if styleData.flashFrame then
		styleData.flashFrame:SetAlpha(0)
	end
end

function Skin:ResetStyleData(styleData)
	if not styleData or not styleData.iconTexture then
		return
	end

	ResetTexCoord(styleData.iconTexture)

	if styleData.cooldownFrame and type(styleData.cooldownFrame.SetUseCircularEdge) == "function" then
		styleData.cooldownFrame:SetUseCircularEdge(true)
	end
	if styleData.cooldownFrame and type(styleData.cooldownFrame.SetSwipeTexture) == "function" then
		styleData.cooldownFrame:SetSwipeTexture(styleData.defaultSwipeTexture or DEFAULT_VIEWER_SWIPE_TEXTURE, 1, 1, 1, 1)
	end

	for _, maskRegion in ipairs(styleData.maskRegions or {}) do
		SafeCall(styleData.iconTexture, "AddMaskTexture", maskRegion)
		if type(maskRegion.Show) == "function" then
			maskRegion:Show()
		end
		if type(maskRegion.SetAtlas) == "function" and styleData.defaultMaskAtlas then
			maskRegion:SetAtlas(styleData.defaultMaskAtlas)
		end
	end

	for _, overlayRegion in ipairs(styleData.overlayRegions or {}) do
		if type(overlayRegion.Show) == "function" then
			overlayRegion:Show()
		end
		if type(overlayRegion.SetAtlas) == "function" and styleData.defaultOverlayAtlas then
			overlayRegion:SetAtlas(styleData.defaultOverlayAtlas)
		end
	end

	for _, swipeTexture in ipairs(styleData.swipeTextures or {}) do
		ResetTexCoord(swipeTexture)
	end

	if styleData.borderFrame then
		styleData.borderFrame:Hide()
	end
	if styleData.flashFrame then
		if styleData.flashAnimation and styleData.flashAnimation:IsPlaying() then
			styleData.flashAnimation:Stop()
		end
		styleData.flashFrame:Hide()
	end
end

function Skin:ApplyToRuntimeButton(button, entry, visual)
	if not button then
		return
	end

	if not self:IsEnabled() then
		self:ResetStyleData(self:BuildRuntimeButtonData(button))
		return
	end

	self:InstallRuntimeFlashHooks(button)
	self:ApplyStyleData(self:BuildRuntimeButtonData(button), self:GetRuntimeState(entry, visual))
end

function Skin:ApplyToCooldownViewerItem(itemFrame)
	if not itemFrame then
		return
	end

	local styleData = self:BuildCooldownViewerData(itemFrame)
	if not styleData then
		return
	end

	if not self:IsEnabled() then
		self:ResetStyleData(styleData)
		if itemFrame.CooldownFlash and itemFrame.CooldownFlash.Flipbook and type(itemFrame.CooldownFlash.Flipbook.Show) == "function" then
			itemFrame.CooldownFlash.Flipbook:Show()
		end
		RestoreProcAlertArt(itemFrame)
		return
	end

	self:InstallViewerFlashHooks(itemFrame)
	SuppressProcAlertArt(itemFrame)
	if itemFrame.CooldownFlash and itemFrame.CooldownFlash.Flipbook and type(itemFrame.CooldownFlash.Flipbook.Hide) == "function" then
		itemFrame.CooldownFlash.Flipbook:Hide()
	end
	self:ApplyStyleData(styleData, ResolveViewerStyleState(itemFrame))
end

function Skin:RefreshActiveCooldownViewerItems()
	for _, frameName in ipairs(COOLDOWN_VIEWER_FRAME_NAMES) do
		local viewer = _G[frameName]
		if viewer and viewer.itemFramePool and type(viewer.itemFramePool.EnumerateActive) == "function" then
			for itemFrame in viewer.itemFramePool:EnumerateActive() do
				self:ApplyToCooldownViewerItem(itemFrame)
			end
		end
	end
end

local function IsCooldownViewerItemFrame(frame)
	return frame and type(frame.GetViewerFrame) == "function" and frame:GetViewerFrame() ~= nil
end

function Skin:InstallHooks()
	if self.hooksInstalled or type(hooksecurefunc) ~= "function" then
		return
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.OnAcquireItemFrame) == "function" then
		hooksecurefunc(CooldownViewerMixin, "OnAcquireItemFrame", function(_, itemFrame)
			Skin:ApplyToCooldownViewerItem(itemFrame)
		end)
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.RefreshData) == "function" then
		hooksecurefunc(CooldownViewerMixin, "RefreshData", function(viewer)
			if viewer and viewer.itemFramePool and type(viewer.itemFramePool.EnumerateActive) == "function" then
				for itemFrame in viewer.itemFramePool:EnumerateActive() do
					Skin:ApplyToCooldownViewerItem(itemFrame)
				end
			end
		end)
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.RefreshLayout) == "function" then
		hooksecurefunc(CooldownViewerMixin, "RefreshLayout", function(viewer)
			if viewer and viewer.itemFramePool and type(viewer.itemFramePool.EnumerateActive) == "function" then
				for itemFrame in viewer.itemFramePool:EnumerateActive() do
					Skin:ApplyToCooldownViewerItem(itemFrame)
				end
			end
		end)
	end

	if CooldownViewerCooldownItemMixin and type(CooldownViewerCooldownItemMixin.RefreshData) == "function" then
		hooksecurefunc(CooldownViewerCooldownItemMixin, "RefreshData", function(itemFrame)
			Skin:ApplyToCooldownViewerItem(itemFrame)
		end)
	end

	if CooldownViewerCooldownItemMixin and type(CooldownViewerCooldownItemMixin.OnSpellActivationOverlayGlowShowEvent) == "function" then
		hooksecurefunc(CooldownViewerCooldownItemMixin, "OnSpellActivationOverlayGlowShowEvent", function(itemFrame)
			Skin:ApplyToCooldownViewerItem(itemFrame)
		end)
	end

	if CooldownViewerCooldownItemMixin and type(CooldownViewerCooldownItemMixin.OnSpellActivationOverlayGlowHideEvent) == "function" then
		hooksecurefunc(CooldownViewerCooldownItemMixin, "OnSpellActivationOverlayGlowHideEvent", function(itemFrame)
			Skin:ApplyToCooldownViewerItem(itemFrame)
		end)
	end

	if CooldownViewerBuffIconItemMixin and type(CooldownViewerBuffIconItemMixin.RefreshData) == "function" then
		hooksecurefunc(CooldownViewerBuffIconItemMixin, "RefreshData", function(itemFrame)
			Skin:ApplyToCooldownViewerItem(itemFrame)
		end)
	end

	if CooldownViewerBuffBarItemMixin and type(CooldownViewerBuffBarItemMixin.RefreshData) == "function" then
		hooksecurefunc(CooldownViewerBuffBarItemMixin, "RefreshData", function(itemFrame)
			Skin:ApplyToCooldownViewerItem(itemFrame)
		end)
	end

	if ActionButtonSpellAlertManager and type(ActionButtonSpellAlertManager.ShowAlert) == "function" then
		hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, actionButton)
			if IsCooldownViewerItemFrame(actionButton) then
				SuppressProcAlertArt(actionButton)
				Skin:ApplyToCooldownViewerItem(actionButton)
			end
		end)
	end

	if ActionButtonSpellAlertManager and type(ActionButtonSpellAlertManager.HideAlert) == "function" then
		hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, actionButton)
			if IsCooldownViewerItemFrame(actionButton) then
				SuppressProcAlertArt(actionButton)
				Skin:ApplyToCooldownViewerItem(actionButton)
			end
		end)
	end

	self.hooksInstalled = true
end

function Skin:Initialize()
	self:InstallHooks()
	self:RefreshActiveCooldownViewerItems()
end

function Skin:RefreshAll()
	self:Initialize()
end
