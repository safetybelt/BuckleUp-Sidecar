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
local PROC_BORDER_COLOR = { r = 1.00, g = 0.91, b = 0.38, a = 1.00 }
local PANDEMIC_BORDER_COLOR = { r = 0.92, g = 0.22, b = 0.22, a = 0.98 }

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

local SetBorderColor
local viewerStyleDataByFrame = setmetatable({}, { __mode = "k" })
local pandemicStateByFrame = setmetatable({}, { __mode = "k" })
-- Tracked buff icon/bar viewers have a different live item structure than Essential/Utility,
-- so their extra cleanup and hooks live in a dedicated helper module.
local trackedBuffSkin = addon.TrackedBuffViewerSkin

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

local function SnapshotFramePoints(frame)
	if not frame or type(frame.GetNumPoints) ~= "function" or type(frame.GetPoint) ~= "function" then
		return nil
	end

	local points = {}
	for index = 1, frame:GetNumPoints() do
		local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(index)
		points[#points + 1] = {
			point = point,
			relativeTo = relativeTo,
			relativePoint = relativePoint,
			xOfs = xOfs,
			yOfs = yOfs,
		}
	end

	return points
end

local function RestoreFramePoints(frame, points)
	if not frame or not points or type(frame.ClearAllPoints) ~= "function" or type(frame.SetPoint) ~= "function" then
		return
	end

	frame:ClearAllPoints()
	for _, pointInfo in ipairs(points) do
		frame:SetPoint(pointInfo.point, pointInfo.relativeTo, pointInfo.relativePoint, pointInfo.xOfs, pointInfo.yOfs)
	end
end

local function CreateSquareOutlineFrame(parent, thickness, frameLevelOffset)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetFrameStrata(parent:GetFrameStrata())
	frame:SetFrameLevel(math.max(parent:GetFrameLevel() + (frameLevelOffset or 0), 1))

	frame.BUTop = frame:CreateTexture(nil, "ARTWORK")
	frame.BUBottom = frame:CreateTexture(nil, "ARTWORK")
	frame.BULeft = frame:CreateTexture(nil, "ARTWORK")
	frame.BURight = frame:CreateTexture(nil, "ARTWORK")

	for _, texture in ipairs({ frame.BUTop, frame.BUBottom, frame.BULeft, frame.BURight }) do
		texture:SetTexture("Interface\\Buttons\\WHITE8X8")
	end

	local edgeSize = thickness or 2
	frame.BUTop:SetPoint("TOPLEFT")
	frame.BUTop:SetPoint("TOPRIGHT")
	frame.BUTop:SetHeight(edgeSize)

	frame.BUBottom:SetPoint("BOTTOMLEFT")
	frame.BUBottom:SetPoint("BOTTOMRIGHT")
	frame.BUBottom:SetHeight(edgeSize)

	frame.BULeft:SetPoint("TOPLEFT")
	frame.BULeft:SetPoint("BOTTOMLEFT")
	frame.BULeft:SetWidth(edgeSize)

	frame.BURight:SetPoint("TOPRIGHT")
	frame.BURight:SetPoint("BOTTOMRIGHT")
	frame.BURight:SetWidth(edgeSize)

	frame:SetAlpha(1)
	frame:Hide()
	return frame
end

local function EnsureBorderFrame(styleData)
	if not styleData or styleData.borderFrame then
		return styleData and styleData.borderFrame or nil
	end

	local parent = styleData.iconOwner or styleData.ownerFrame
	if not parent then
		return nil
	end

	local borderFrame = CreateSquareOutlineFrame(parent, 2, 1)
	borderFrame:SetPoint("TOPLEFT", styleData.iconTexture, "TOPLEFT", -2, 2)
	borderFrame:SetPoint("BOTTOMRIGHT", styleData.iconTexture, "BOTTOMRIGHT", 2, -2)
	borderFrame:Hide()

	styleData.borderFrame = borderFrame
	return borderFrame
end

SetBorderColor = function(frame, colorInfo)
	if not frame or not colorInfo then
		return
	end

	for _, texture in ipairs({ frame.BUTop, frame.BUBottom, frame.BULeft, frame.BURight }) do
		if texture and type(texture.SetVertexColor) == "function" then
			texture:SetVertexColor(colorInfo.r, colorInfo.g, colorInfo.b, colorInfo.a)
		end
	end
end

local function ResolveViewerStyleState(itemFrame)
	local isProcActive = itemFrame and itemFrame.SpellActivationAlert and itemFrame.SpellActivationAlert.IsShown and itemFrame.SpellActivationAlert:IsShown() or false

	return {
		isProcActive = isProcActive,
	}
end

local function SuppressProcAlertArt(itemFrame)
	local alertFrame = itemFrame and itemFrame.SpellActivationAlert
	if not alertFrame then
		return
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
end

local function RestoreProcAlertArt(itemFrame)
	local alertFrame = itemFrame and itemFrame.SpellActivationAlert
	if not alertFrame then
		return
	end

	if alertFrame.IsShown and not alertFrame:IsShown() then
		return
	end

	-- Sidecar only suppresses Blizzard's visible proc subregions, so restoration should
	-- remain equally lightweight: just show those subregions again if the alert frame
	-- itself is active. Replaying Blizzard's alert manager lifecycle here is unnecessary
	-- and risks touching protected internal state during mode switches.
	if alertFrame.ProcStartFlipbook and type(alertFrame.ProcStartFlipbook.Show) == "function" then
		alertFrame.ProcStartFlipbook:Show()
	end
	if alertFrame.ProcLoopFlipbook and type(alertFrame.ProcLoopFlipbook.Show) == "function" then
		alertFrame.ProcLoopFlipbook:Show()
	end
	if alertFrame.ProcAltGlow and type(alertFrame.ProcAltGlow.Show) == "function" then
		alertFrame.ProcAltGlow:Show()
	end
end

function Skin:GetRuntimeState(entry, visual)
	local state = {
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
		isRuntimeButton = true,
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

local function GetViewerName(viewer)
	return viewer and type(viewer.GetName) == "function" and viewer:GetName() or nil
end

local function IsSupportedViewer(viewer)
	local viewerName = GetViewerName(viewer)
	return viewerName == "EssentialCooldownViewer"
		or viewerName == "UtilityCooldownViewer"
		or (trackedBuffSkin and trackedBuffSkin:IsTrackedBuffViewer(viewer))
end

local function IsEssentialUtilityViewer(viewer)
	local viewerName = GetViewerName(viewer)
	return viewerName == "EssentialCooldownViewer" or viewerName == "UtilityCooldownViewer"
end

local function CollectKnownViewerRegions(styleData)
	if not styleData then
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

	if styleData.cooldownFrame and type(styleData.cooldownFrame.GetRegions) == "function" then
		for _, region in ipairs({ styleData.cooldownFrame:GetRegions() }) do
			if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "Texture" then
				local texturePath = type(region.GetTexture) == "function" and region:GetTexture() or nil
				if texturePath == DEFAULT_VIEWER_SWIPE_TEXTURE then
					styleData.swipeTextures[#styleData.swipeTextures + 1] = region
				end
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
	if viewerStyleDataByFrame[itemFrame] then
		return viewerStyleDataByFrame[itemFrame]
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
		isRuntimeButton = false,
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

	CollectKnownViewerRegions(styleData)
	styleData.maskRegions = DeduplicateRegions(styleData.maskRegions)
	styleData.overlayRegions = DeduplicateRegions(styleData.overlayRegions)
	styleData.swipeTextures = DeduplicateRegions(styleData.swipeTextures)

	viewerStyleDataByFrame[itemFrame] = styleData
	return styleData
end

local function IsSupportedViewerItem(itemFrame)
	local viewer = itemFrame and type(itemFrame.GetViewerFrame) == "function" and itemFrame:GetViewerFrame() or nil
	return itemFrame and viewer ~= nil and IsSupportedViewer(viewer)
end

local function IsEssentialUtilityViewerItem(itemFrame)
	local viewer = itemFrame and type(itemFrame.GetViewerFrame) == "function" and itemFrame:GetViewerFrame() or nil
	return itemFrame and itemFrame.CooldownFlash ~= nil and viewer ~= nil and IsEssentialUtilityViewer(viewer)
end

local function HasManagedPandemicState(pandemicFrame)
	local state = pandemicFrame and pandemicStateByFrame[pandemicFrame] or nil
	return state and (
		state.squareBorder ~= nil
		or state.suppressed == true
		or state.itemFrame ~= nil
	) or false
end

local function HasManagedViewerState(itemFrame)
	return itemFrame and (
		viewerStyleDataByFrame[itemFrame] ~= nil
		or HasManagedPandemicState(itemFrame.PandemicIcon)
	)
end

local function GetPandemicState(pandemicFrame, createIfMissing)
	if not pandemicFrame then
		return nil
	end

	local state = pandemicStateByFrame[pandemicFrame]
	if not state and createIfMissing then
		state = {}
		pandemicStateByFrame[pandemicFrame] = state
	end

	return state
end

local function SuppressViewerReadyFlash(styleData)
	local cooldownFlashFrame = styleData and styleData.ownerFrame and styleData.ownerFrame.CooldownFlash
	if not cooldownFlashFrame then
		return
	end

	-- Unified style currently suppresses Blizzard viewer ready-flash outright rather than
	-- trying to replace it. Sidecar does not own a production ready-flash system today.
	if cooldownFlashFrame.FlashAnim and type(cooldownFlashFrame.FlashAnim.Stop) == "function" then
		cooldownFlashFrame.FlashAnim:Stop()
	end
	if cooldownFlashFrame.Flipbook and type(cooldownFlashFrame.Flipbook.Hide) == "function" then
		cooldownFlashFrame.Flipbook:Hide()
	end
	if type(cooldownFlashFrame.Hide) == "function" then
		cooldownFlashFrame:Hide()
	end
end

local function RestoreViewerReadyFlashPresentation(styleData)
	local cooldownFlashFrame = styleData and styleData.ownerFrame and styleData.ownerFrame.CooldownFlash
	if not cooldownFlashFrame then
		return
	end

	if type(cooldownFlashFrame.Show) == "function" then
		cooldownFlashFrame:Show()
	end
	if cooldownFlashFrame.Flipbook and type(cooldownFlashFrame.Flipbook.Show) == "function" then
		cooldownFlashFrame.Flipbook:Show()
	end
end

local function EnsureViewerReadyFlashSuppressionHooks(styleData)
	local cooldownFlashFrame = styleData and styleData.ownerFrame and styleData.ownerFrame.CooldownFlash
	if not cooldownFlashFrame or styleData.viewerReadyFlashHooksInstalled then
		return
	end

	styleData.viewerReadyFlashHooksInstalled = true

	if cooldownFlashFrame.FlashAnim and type(hooksecurefunc) == "function" then
		hooksecurefunc(cooldownFlashFrame.FlashAnim, "Play", function()
			if Skin:IsEnabled() then
				SuppressViewerReadyFlash(styleData)
			end
		end)
	end

	if type(cooldownFlashFrame.HookScript) == "function" then
		cooldownFlashFrame:HookScript("OnShow", function()
			if Skin:IsEnabled() then
				SuppressViewerReadyFlash(styleData)
			end
		end)
	end

	if cooldownFlashFrame.Flipbook and type(hooksecurefunc) == "function" then
		hooksecurefunc(cooldownFlashFrame.Flipbook, "Show", function()
			if Skin:IsEnabled() then
				SuppressViewerReadyFlash(styleData)
			end
		end)
	end
end

local function EnsurePandemicSquareBorder(pandemicFrame, iconTexture)
	if not pandemicFrame or not iconTexture then
		return nil
	end

	local state = GetPandemicState(pandemicFrame, true)
	local border = state.squareBorder
	if not border then
		border = CreateSquareOutlineFrame(pandemicFrame, 2, 2)
		state.squareBorder = border
	end

	border:ClearAllPoints()
	border:SetPoint("TOPLEFT", iconTexture, "TOPLEFT", -2, 2)
	border:SetPoint("BOTTOMRIGHT", iconTexture, "BOTTOMRIGHT", 2, -2)
	border:SetFrameStrata(pandemicFrame:GetFrameStrata())
	border:SetFrameLevel(math.max(pandemicFrame:GetFrameLevel() + 2, 1))
	SetBorderColor(border, PANDEMIC_BORDER_COLOR)
	return border
end

local function SetPandemicArtSuppressed(pandemicFrame, suppressed)
	if not pandemicFrame then
		return
	end

	local state = GetPandemicState(pandemicFrame, true)

	local borderTexture = pandemicFrame.Border and pandemicFrame.Border.Border or nil
	local fxFrame = pandemicFrame.FX

	if borderTexture then
		if suppressed and type(borderTexture.Hide) == "function" then
			borderTexture:Hide()
		elseif not suppressed and type(borderTexture.Show) == "function" then
			borderTexture:Show()
		end
	end

	if fxFrame then
		if suppressed and type(fxFrame.Hide) == "function" then
			fxFrame:Hide()
		elseif not suppressed and type(fxFrame.Show) == "function" then
			fxFrame:Show()
		end
	end

	state.suppressed = suppressed and true or false
end

local function ResetPandemicFrameStyle(pandemicFrame)
	if not pandemicFrame then
		return
	end

	SetPandemicArtSuppressed(pandemicFrame, false)
	local state = GetPandemicState(pandemicFrame, false)
	if state and state.squareBorder then
		state.squareBorder:Hide()
	end
	if state then
		state.suppressed = false
		state.itemFrame = nil
	end
end

local function ApplyPandemicStyleToItem(itemFrame)
	if not IsEssentialUtilityViewerItem(itemFrame) then
		return
	end

	local styleData = Skin:BuildCooldownViewerData(itemFrame)
	local pandemicFrame = itemFrame and itemFrame.PandemicIcon or nil
	if not styleData or not pandemicFrame or not styleData.iconTexture then
		return
	end

	local state = GetPandemicState(pandemicFrame, true)
	state.itemFrame = itemFrame
	local squareBorder = EnsurePandemicSquareBorder(pandemicFrame, styleData.iconTexture)
	if not state.suppressed then
		SetPandemicArtSuppressed(pandemicFrame, true)
	end
	if squareBorder then
		squareBorder:Show()
	end
end

local function EnsurePandemicFrameHooks(pandemicFrame)
	local state = GetPandemicState(pandemicFrame, true)
	if not pandemicFrame or state.hooksInstalled or type(pandemicFrame.HookScript) ~= "function" then
		return
	end

	state.hooksInstalled = true
	pandemicFrame:HookScript("OnShow", function(frame)
		local frameState = GetPandemicState(frame, false)
		local itemFrame = frameState and frameState.itemFrame or nil
		if Skin:IsEnabled() and itemFrame then
			ApplyPandemicStyleToItem(itemFrame)
		end
	end)
	pandemicFrame:HookScript("OnHide", function(frame)
		ResetPandemicFrameStyle(frame)
	end)

	local borderTexture = pandemicFrame.Border and pandemicFrame.Border.Border or nil
	if borderTexture and type(hooksecurefunc) == "function" and not state.borderShowHookInstalled then
		state.borderShowHookInstalled = true
		-- Blizzard can re-show the rounded pandemic border after the pooled frame is already
		-- active, so we clamp that exact subregion instead of broadening the OnUpdate shim.
		hooksecurefunc(borderTexture, "Show", function(region)
			local frameState = GetPandemicState(pandemicFrame, false)
			if Skin:IsEnabled() and frameState and frameState.itemFrame and type(region.Hide) == "function" then
				region:Hide()
			end
		end)
	end

	local fxFrame = pandemicFrame.FX
	if fxFrame and type(hooksecurefunc) == "function" and not state.fxShowHookInstalled then
		state.fxShowHookInstalled = true
		hooksecurefunc(fxFrame, "Show", function(frame)
			local frameState = GetPandemicState(pandemicFrame, false)
			if Skin:IsEnabled() and frameState and frameState.itemFrame and type(frame.Hide) == "function" then
				frame:Hide()
			end
		end)
	end
end

function Skin:ApplyStyleData(styleData, styleState)
	if not styleData or not styleData.iconTexture then
		return
	end

	styleState = styleState or {}

	local borderFrame = EnsureBorderFrame(styleData)

	ApplyTexCoord(styleData.iconTexture)

	if styleData.cooldownFrame and type(styleData.cooldownFrame.SetUseCircularEdge) == "function" then
		styleData.cooldownFrame:SetUseCircularEdge(false)
	end
	-- Sidecar runtime buttons do not implement a production cooldown-ready flash. In
	-- unified style we only suppress the built-in cooldown completion visuals so runtime
	-- buttons stay visually aligned with the rest of the theme.
	if styleData.isRuntimeButton and styleData.cooldownFrame and type(styleData.cooldownFrame.SetDrawBling) == "function" then
		styleData.cooldownFrame:SetDrawBling(false)
	end
	if styleData.isRuntimeButton and styleData.cooldownFrame and type(styleData.cooldownFrame.SetDrawEdge) == "function" then
		styleData.cooldownFrame:SetDrawEdge(false)
	end
	if styleData.cooldownFrame and type(styleData.cooldownFrame.SetSwipeTexture) == "function" then
		styleData.cooldownFrame:SetSwipeTexture(SQUARE_SWIPE_TEXTURE, 1, 1, 1, 1)
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
	if trackedBuffSkin then
		borderColor = trackedBuffSkin:GetBorderColorOverride(styleData.ownerFrame) or borderColor
	end
	if styleState.isProcActive then
		borderColor = PROC_BORDER_COLOR
	end

	if borderFrame then
		SetBorderColor(borderFrame, borderColor)
		borderFrame:Show()
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
	if styleData.isRuntimeButton and styleData.cooldownFrame and type(styleData.cooldownFrame.SetDrawBling) == "function" then
		styleData.cooldownFrame:SetDrawBling(true)
	end
	if styleData.isRuntimeButton and styleData.cooldownFrame and type(styleData.cooldownFrame.SetDrawEdge) == "function" then
		styleData.cooldownFrame:SetDrawEdge(true)
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

	if trackedBuffSkin then
		trackedBuffSkin:ResetBorderStyle(styleData.ownerFrame)
	end

	if styleData.borderFrame then
		styleData.borderFrame:Hide()
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

	self:ApplyStyleData(self:BuildRuntimeButtonData(button), self:GetRuntimeState(entry, visual))
end

function Skin:ApplyToCooldownViewerItem(itemFrame, allowResetWhenDisabled)
	if not IsSupportedViewerItem(itemFrame) then
		return
	end

	if not self:IsEnabled() and not allowResetWhenDisabled then
		return
	end

	if not self:IsEnabled() then
		if not HasManagedViewerState(itemFrame) then
			return
		end

		local styleData = viewerStyleDataByFrame[itemFrame]
		if styleData then
			self:ResetStyleData(styleData)
			RestoreViewerReadyFlashPresentation(styleData)
		end
		if itemFrame.PandemicIcon and HasManagedPandemicState(itemFrame.PandemicIcon) then
			ResetPandemicFrameStyle(itemFrame.PandemicIcon)
		end
		RestoreProcAlertArt(itemFrame)
		return
	end

	local styleData = self:BuildCooldownViewerData(itemFrame)
	if not styleData then
		return
	end

	SuppressProcAlertArt(itemFrame)
	EnsureViewerReadyFlashSuppressionHooks(styleData)
	SuppressViewerReadyFlash(styleData)
	self:ApplyStyleData(styleData, ResolveViewerStyleState(itemFrame))
	if itemFrame.PandemicIcon and IsEssentialUtilityViewerItem(itemFrame) then
		EnsurePandemicFrameHooks(itemFrame.PandemicIcon)
		ApplyPandemicStyleToItem(itemFrame)
	end
end

function Skin:RefreshActiveCooldownViewerItems(allowResetWhenDisabled)
	for _, frameName in ipairs(COOLDOWN_VIEWER_FRAME_NAMES) do
		local viewer = _G[frameName]
		self:ApplyToViewer(viewer, allowResetWhenDisabled)
	end
end

local function IsCooldownViewerItemFrame(frame)
	return frame and type(frame.GetViewerFrame) == "function" and frame:GetViewerFrame() ~= nil
end

function Skin:ApplyToViewer(viewer, allowResetWhenDisabled)
	if not viewer or not IsSupportedViewer(viewer) or not viewer.itemFramePool or type(viewer.itemFramePool.EnumerateActive) ~= "function" then
		return
	end

	for itemFrame in viewer.itemFramePool:EnumerateActive() do
		self:ApplyToCooldownViewerItem(itemFrame, allowResetWhenDisabled)
	end
end

function Skin:RefreshViewerPandemicFrames(viewer)
	if not self:IsEnabled() then
		return
	end

	if not viewer or not IsEssentialUtilityViewer(viewer) or not viewer.itemFramePool or type(viewer.itemFramePool.EnumerateActive) ~= "function" then
		return
	end

	for itemFrame in viewer.itemFramePool:EnumerateActive() do
		if itemFrame.PandemicIcon and itemFrame.PandemicIcon.IsShown and itemFrame.PandemicIcon:IsShown() then
			EnsurePandemicFrameHooks(itemFrame.PandemicIcon)
			ApplyPandemicStyleToItem(itemFrame)
		end
	end
end

function Skin:InstallHooks()
	if self.hooksInstalled or type(hooksecurefunc) ~= "function" then
		return
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.OnAcquireItemFrame) == "function" then
		hooksecurefunc(CooldownViewerMixin, "OnAcquireItemFrame", function(_, itemFrame)
			if not Skin:IsEnabled() then
				return
			end
			Skin:ApplyToCooldownViewerItem(itemFrame)
		end)
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.RefreshData) == "function" then
		hooksecurefunc(CooldownViewerMixin, "RefreshData", function(viewer)
			if not Skin:IsEnabled() then
				return
			end
			Skin:ApplyToViewer(viewer)
		end)
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.RefreshLayout) == "function" then
		hooksecurefunc(CooldownViewerMixin, "RefreshLayout", function(viewer)
			if not Skin:IsEnabled() then
				return
			end
			Skin:ApplyToViewer(viewer)
		end)
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.OnUpdate) == "function" then
		hooksecurefunc(CooldownViewerMixin, "OnUpdate", function(viewer)
			if not Skin:IsEnabled() then
				return
			end
			-- Blizzard's pooled pandemic frame can paint before the show/setup hooks are enough
			-- on their own, so we keep this narrow refresh assist to catch shown pandemic frames
			-- and suppress the rounded art before it lingers on screen.
			Skin:RefreshViewerPandemicFrames(viewer)
			if trackedBuffSkin then
				trackedBuffSkin:RefreshViewerPandemicFrames(viewer)
			end
		end)
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.SetupPandemicStateFrameForItem) == "function" then
		hooksecurefunc(CooldownViewerMixin, "SetupPandemicStateFrameForItem", function(viewer, itemFrame)
			if not Skin:IsEnabled() then
				return
			end
			if not IsEssentialUtilityViewer(viewer) then
				return
			end
			if itemFrame and itemFrame.PandemicIcon then
				EnsurePandemicFrameHooks(itemFrame.PandemicIcon)
			end
			ApplyPandemicStyleToItem(itemFrame)
		end)
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.AnchorPandemicStateFrame) == "function" then
		hooksecurefunc(CooldownViewerMixin, "AnchorPandemicStateFrame", function(viewer, pandemicFrame, itemFrame)
			if not Skin:IsEnabled() then
				return
			end
			if not IsEssentialUtilityViewer(viewer) then
				return
			end
			if pandemicFrame then
				EnsurePandemicFrameHooks(pandemicFrame)
			end
			ApplyPandemicStyleToItem(itemFrame)
		end)
	end

	if CooldownViewerCooldownItemMixin and type(CooldownViewerCooldownItemMixin.RefreshData) == "function" then
		hooksecurefunc(CooldownViewerCooldownItemMixin, "RefreshData", function(itemFrame)
			if not Skin:IsEnabled() then
				return
			end
			Skin:ApplyToCooldownViewerItem(itemFrame)
		end)
	end

	if CooldownViewerCooldownItemMixin and type(CooldownViewerCooldownItemMixin.OnSpellActivationOverlayGlowShowEvent) == "function" then
		hooksecurefunc(CooldownViewerCooldownItemMixin, "OnSpellActivationOverlayGlowShowEvent", function(itemFrame)
			if not Skin:IsEnabled() then
				return
			end
			Skin:ApplyToCooldownViewerItem(itemFrame)
		end)
	end

	if CooldownViewerCooldownItemMixin and type(CooldownViewerCooldownItemMixin.OnSpellActivationOverlayGlowHideEvent) == "function" then
		hooksecurefunc(CooldownViewerCooldownItemMixin, "OnSpellActivationOverlayGlowHideEvent", function(itemFrame)
			if not Skin:IsEnabled() then
				return
			end
			Skin:ApplyToCooldownViewerItem(itemFrame)
		end)
	end

	if trackedBuffSkin then
		trackedBuffSkin:InstallHooks(function(itemFrame)
			if not Skin:IsEnabled() then
				return
			end
			Skin:ApplyToCooldownViewerItem(itemFrame)
		end)
	end

	if CooldownViewerItemMixin and type(CooldownViewerItemMixin.ShowPandemicStateFrame) == "function" then
		hooksecurefunc(CooldownViewerItemMixin, "ShowPandemicStateFrame", function(itemFrame)
			if not Skin:IsEnabled() then
				return
			end
			if not IsEssentialUtilityViewerItem(itemFrame) then
				return
			end
			if itemFrame and itemFrame.PandemicIcon then
				EnsurePandemicFrameHooks(itemFrame.PandemicIcon)
			end
			ApplyPandemicStyleToItem(itemFrame)
		end)
	end

	if CooldownViewerItemMixin and type(CooldownViewerItemMixin.HidePandemicStateFrame) == "function" then
		hooksecurefunc(CooldownViewerItemMixin, "HidePandemicStateFrame", function(itemFrame)
			if IsEssentialUtilityViewerItem(itemFrame) and itemFrame.PandemicIcon and HasManagedPandemicState(itemFrame.PandemicIcon) then
				ResetPandemicFrameStyle(itemFrame.PandemicIcon)
			end
		end)
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.HidePandemicStateFrame) == "function" then
		hooksecurefunc(CooldownViewerMixin, "HidePandemicStateFrame", function(viewer, stateFrame)
			if IsEssentialUtilityViewer(viewer) and HasManagedPandemicState(stateFrame) then
				ResetPandemicFrameStyle(stateFrame)
			end
		end)
	end

	if ActionButtonSpellAlertManager and type(ActionButtonSpellAlertManager.ShowAlert) == "function" then
		hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, actionButton)
			if IsCooldownViewerItemFrame(actionButton) then
				if not Skin:IsEnabled() then
					return
				end
				Skin:ApplyToCooldownViewerItem(actionButton)
			end
		end)
	end

	if ActionButtonSpellAlertManager and type(ActionButtonSpellAlertManager.HideAlert) == "function" then
		hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, actionButton)
			if IsCooldownViewerItemFrame(actionButton) then
				if not Skin:IsEnabled() then
					return
				end
				Skin:ApplyToCooldownViewerItem(actionButton)
			end
		end)
	end

	self.hooksInstalled = true
end

function Skin:Initialize()
	self:InstallHooks()
	if self:IsEnabled() then
		self:RefreshActiveCooldownViewerItems(false)
	end
end

function Skin:RefreshAll()
	self:InstallHooks()
	self:RefreshActiveCooldownViewerItems(not self:IsEnabled())
end
