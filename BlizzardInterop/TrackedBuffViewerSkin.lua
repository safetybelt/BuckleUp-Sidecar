local addonName, addonTable = ...
local addon = addonTable or BuckleUpSidecar

local TrackedBuffSkin = {}
addon.TrackedBuffViewerSkin = TrackedBuffSkin

local DEFAULT_BORDER_COLOR = { r = 0.10, g = 0.10, b = 0.10, a = 0.96 }
local PANDEMIC_BORDER_COLOR = { r = 0.92, g = 0.22, b = 0.22, a = 0.98 }
local debuffBorderStateByFrame = setmetatable({}, { __mode = "k" })
local pandemicStateByFrame = setmetatable({}, { __mode = "k" })

local function GetViewerName(viewer)
	return viewer and type(viewer.GetName) == "function" and viewer:GetName() or nil
end

function TrackedBuffSkin:IsTrackedBuffViewer(viewer)
	local viewerName = GetViewerName(viewer)
	return viewerName == "BuffIconCooldownViewer" or viewerName == "BuffBarCooldownViewer"
end

function TrackedBuffSkin:IsTrackedBuffItem(itemFrame)
	local viewer = itemFrame and type(itemFrame.GetViewerFrame) == "function" and itemFrame:GetViewerFrame() or nil
	return itemFrame and viewer ~= nil and self:IsTrackedBuffViewer(viewer)
end

local function IsTrackedBuffIconViewer(viewer)
	local viewerName = GetViewerName(viewer)
	return viewerName == "BuffIconCooldownViewer"
end

function TrackedBuffSkin:IsTrackedBuffIconItem(itemFrame)
	local viewer = itemFrame and type(itemFrame.GetViewerFrame) == "function" and itemFrame:GetViewerFrame() or nil
	return itemFrame and viewer ~= nil and IsTrackedBuffIconViewer(viewer)
end

local function IsUnifiedSkinEnabled()
	return addon.Profile and addon.Profile.IsUnifiedVisualStyleEnabled and addon.Profile:IsUnifiedVisualStyleEnabled()
end

local function SnapshotRegionVisualState(region)
	if not region or type(region.GetObjectType) ~= "function" then
		return nil
	end

	return {
		region = region,
		wasShown = type(region.IsShown) == "function" and region:IsShown() or nil,
		alpha = type(region.GetAlpha) == "function" and region:GetAlpha() or nil,
		atlas = (type(region.GetAtlas) == "function" and region:GetAtlas() ~= nil) and tostring(region:GetAtlas()) or nil,
		texture = type(region.GetTexture) == "function" and region:GetTexture() or nil,
	}
end

local function RestoreRegionVisualState(state)
	local region = state and state.region or nil
	if not region then
		return
	end

	if type(region.SetAlpha) == "function" and state.alpha ~= nil then
		region:SetAlpha(state.alpha)
	end
	if type(region.SetAtlas) == "function" and state.atlas ~= nil then
		region:SetAtlas(state.atlas)
	end
	if type(region.SetTexture) == "function" and state.texture ~= nil then
		region:SetTexture(state.texture)
	end

	if state.wasShown ~= nil then
		if state.wasShown and type(region.Show) == "function" then
			region:Show()
		elseif not state.wasShown and type(region.Hide) == "function" then
			region:Hide()
		end
	end
end

local function GetDebuffBorderState(borderFrame, createIfMissing)
	if not borderFrame then
		return nil
	end

	local state = debuffBorderStateByFrame[borderFrame]
	if not state and createIfMissing then
		state = {}
		debuffBorderStateByFrame[borderFrame] = state
	end
	return state
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

local function GetTrackedBuffDebuffBorder(itemFrame)
	if not itemFrame then
		return nil
	end

	return itemFrame.DebuffBorder or (itemFrame.Icon and itemFrame.Icon.DebuffBorder) or nil
end

local function GetTrackedBuffPandemicFrame(itemFrame)
	if not TrackedBuffSkin:IsTrackedBuffIconItem(itemFrame) then
		return nil
	end

	return itemFrame and itemFrame.PandemicIcon or nil
end

local function EnsureDebuffBorderHooks(borderFrame, itemFrame)
	if not borderFrame or type(borderFrame.HookScript) ~= "function" then
		return
	end

	local state = GetDebuffBorderState(borderFrame, true)
	state.itemFrame = itemFrame or state.itemFrame
	if state.frameHooksInstalled then
		return
	end

	-- Blizzard can show or hide tracked-buff debuff borders after the normal item refresh
	-- path has already run, so we bounce back into the shared viewer restyle when that
	-- border frame changes visibility.
	borderFrame:HookScript("OnShow", function(frame)
		local borderState = GetDebuffBorderState(frame, false)
		local ownerItemFrame = borderState and borderState.itemFrame or nil
		if ownerItemFrame and TrackedBuffSkin.restyleTrackedBuffItem then
			TrackedBuffSkin.restyleTrackedBuffItem(ownerItemFrame)
		end
	end)

	borderFrame:HookScript("OnHide", function(frame)
		local borderState = GetDebuffBorderState(frame, false)
		local ownerItemFrame = borderState and borderState.itemFrame or nil
		if ownerItemFrame and TrackedBuffSkin.restyleTrackedBuffItem then
			TrackedBuffSkin.restyleTrackedBuffItem(ownerItemFrame)
		end
	end)

	state.frameHooksInstalled = true
end

local function ResolveItemFrameFromBorderFrame(borderFrame)
	if not borderFrame or type(borderFrame.GetParent) ~= "function" then
		return nil
	end

	local parent = borderFrame:GetParent()
	if parent and type(parent.GetViewerFrame) == "function" and parent:GetViewerFrame() ~= nil then
		return parent
	end

	local grandParent = parent and type(parent.GetParent) == "function" and parent:GetParent() or nil
	if grandParent and type(grandParent.GetViewerFrame) == "function" and grandParent:GetViewerFrame() ~= nil then
		return grandParent
	end

	return parent
end

local function ResolveItemFrameFromPandemicFrame(pandemicFrame)
	if not pandemicFrame or type(pandemicFrame.GetParent) ~= "function" then
		return nil
	end

	local parent = pandemicFrame:GetParent()
	if parent and type(parent.GetViewerFrame) == "function" and parent:GetViewerFrame() ~= nil then
		return parent
	end

	local grandParent = parent and type(parent.GetParent) == "function" and parent:GetParent() or nil
	if grandParent and type(grandParent.GetViewerFrame) == "function" and grandParent:GetViewerFrame() ~= nil then
		return grandParent
	end

	return nil
end

local function FindVisibleDebuffRegion(borderFrame)
	if not borderFrame or type(borderFrame.GetRegions) ~= "function" then
		return nil
	end

	local fallbackRegion = nil
	for _, region in ipairs({ borderFrame:GetRegions() }) do
		if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "Texture" then
			fallbackRegion = fallbackRegion or region
			if type(region.IsShown) == "function" and region:IsShown() then
				return region
			end
		end
	end

	return fallbackRegion
end

local function SnapshotPandemicArtState(pandemicFrame)
	if not pandemicFrame then
		return nil
	end

	return {
		borderTexture = SnapshotRegionVisualState(pandemicFrame.Border and pandemicFrame.Border.Border or nil),
		fxFrameShown = pandemicFrame.FX and type(pandemicFrame.FX.IsShown) == "function" and pandemicFrame.FX:IsShown() or nil,
	}
end

local function RestorePandemicArtState(pandemicFrame, state)
	if not pandemicFrame or not state then
		return
	end

	RestoreRegionVisualState(state.borderTexture)
	if pandemicFrame.FX and state.fxFrameShown ~= nil then
		if state.fxFrameShown and type(pandemicFrame.FX.Show) == "function" then
			pandemicFrame.FX:Show()
		elseif not state.fxFrameShown and type(pandemicFrame.FX.Hide) == "function" then
			pandemicFrame.FX:Hide()
		end
	end
end

local function ResolveBorderColor(_borderFrame, region)
	if not region then
		return DEFAULT_BORDER_COLOR
	end

	if type(region.GetVertexColor) == "function" then
		local r, g, b, a = region:GetVertexColor()
		if r ~= nil and g ~= nil and b ~= nil then
			local alpha = a or 1
			-- Blizzard can leave these borders at white, so in that case we fall back to the
			-- normal unified square border color instead of decoding aura type ourselves.
			if math.abs(r - 1) > 0.01 or math.abs(g - 1) > 0.01 or math.abs(b - 1) > 0.01 then
				return { r = r, g = g, b = b, a = alpha }
			end
		end
	end

	return DEFAULT_BORDER_COLOR
end

local function SetPandemicArtSuppressed(pandemicFrame, suppressed)
	if not pandemicFrame then
		return
	end

	local state = GetPandemicState(pandemicFrame, true)
	local borderTexture = pandemicFrame.Border and pandemicFrame.Border.Border or nil
	local fxFrame = pandemicFrame.FX

	if suppressed and not state.suppressed then
		state.artState = SnapshotPandemicArtState(pandemicFrame)
	end

	if borderTexture then
		if suppressed then
			if type(borderTexture.Hide) == "function" then
				borderTexture:Hide()
			end
		elseif type(borderTexture.Show) == "function" then
			borderTexture:Show()
		end
	end

	if fxFrame then
		if suppressed then
			if type(fxFrame.Hide) == "function" then
				fxFrame:Hide()
			end
		elseif type(fxFrame.Show) == "function" then
			fxFrame:Show()
		end
	end

	if not suppressed and state.suppressed then
		RestorePandemicArtState(pandemicFrame, state.artState)
		state.artState = nil
	end

	state.suppressed = suppressed and true or false
end

local function EnsurePandemicRegionHooks(pandemicFrame)
	local state = GetPandemicState(pandemicFrame, true)
	if state.regionHooksInstalled or type(hooksecurefunc) ~= "function" then
		return
	end

	local borderTexture = pandemicFrame.Border and pandemicFrame.Border.Border or nil
	if borderTexture and type(borderTexture.Show) == "function" then
		hooksecurefunc(borderTexture, "Show", function(region)
			local pandemicState = GetPandemicState(pandemicFrame, false)
			if IsUnifiedSkinEnabled() and pandemicState and pandemicState.suppressed and type(region.Hide) == "function" then
				region:Hide()
			end
		end)
	end

	local fxFrame = pandemicFrame.FX
	if fxFrame and type(fxFrame.Show) == "function" then
		hooksecurefunc(fxFrame, "Show", function(frame)
			local pandemicState = GetPandemicState(pandemicFrame, false)
			if IsUnifiedSkinEnabled() and pandemicState and pandemicState.suppressed and type(frame.Hide) == "function" then
				frame:Hide()
			end
		end)
	end

	state.regionHooksInstalled = true
end

local function EnsurePandemicFrameHooks(pandemicFrame, itemFrame)
	if not pandemicFrame or type(pandemicFrame.HookScript) ~= "function" then
		return
	end

	local state = GetPandemicState(pandemicFrame, true)
	state.itemFrame = itemFrame or state.itemFrame
	EnsurePandemicRegionHooks(pandemicFrame)
	if state.frameHooksInstalled then
		return
	end

	pandemicFrame:HookScript("OnShow", function(frame)
		local pandemicState = GetPandemicState(frame, false)
		local ownerItemFrame = pandemicState and pandemicState.itemFrame or nil
		if ownerItemFrame and TrackedBuffSkin.restyleTrackedBuffItem then
			TrackedBuffSkin.restyleTrackedBuffItem(ownerItemFrame)
		end
	end)

	pandemicFrame:HookScript("OnHide", function(frame)
		local pandemicState = GetPandemicState(frame, false)
		local ownerItemFrame = pandemicState and pandemicState.itemFrame or nil
		if ownerItemFrame and TrackedBuffSkin.restyleTrackedBuffItem then
			TrackedBuffSkin.restyleTrackedBuffItem(ownerItemFrame)
		end
	end)

	state.frameHooksInstalled = true
end

local function EnsureRoundedBorderRegionHooks(borderFrame)
	if not borderFrame or type(borderFrame.GetRegions) ~= "function" or type(hooksecurefunc) ~= "function" then
		return
	end

	local state = GetDebuffBorderState(borderFrame, true)
	if state.regionHooksInstalled then
		return
	end

	for _, region in ipairs({ borderFrame:GetRegions() }) do
		if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "Texture" and type(region.Show) == "function" then
			hooksecurefunc(region, "Show", function(textureRegion)
				local borderState = GetDebuffBorderState(borderFrame, false)
				if IsUnifiedSkinEnabled() and borderState and borderState.suppressed then
					if type(textureRegion.SetAtlas) == "function" then
						textureRegion:SetAtlas(nil)
					end
					if type(textureRegion.SetTexture) == "function" then
						textureRegion:SetTexture(nil)
					end
					if type(textureRegion.SetAlpha) == "function" then
						textureRegion:SetAlpha(0)
					end
					if type(textureRegion.Hide) == "function" then
						textureRegion:Hide()
					end
				end
			end)
		end
	end

	state.regionHooksInstalled = true
end

local function SuppressRoundedDebuffBorder(borderFrame)
	if not borderFrame or type(borderFrame.GetRegions) ~= "function" then
		return
	end

	local state = GetDebuffBorderState(borderFrame, true)
	EnsureRoundedBorderRegionHooks(borderFrame)
	if state.suppressed then
		return
	end

	state.regionStates = {}
	state.frameAlpha = type(borderFrame.GetAlpha) == "function" and borderFrame:GetAlpha() or nil
	for _, region in ipairs({ borderFrame:GetRegions() }) do
		if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "Texture" then
			state.regionStates[#state.regionStates + 1] = SnapshotRegionVisualState(region)
			if type(region.SetAtlas) == "function" then
				region:SetAtlas(nil)
			end
			if type(region.SetTexture) == "function" then
				region:SetTexture(nil)
			end
			if type(region.SetAlpha) == "function" then
				region:SetAlpha(0)
			end
			if type(region.Hide) == "function" then
				region:Hide()
			end
		end
	end
	if type(borderFrame.SetAlpha) == "function" then
		borderFrame:SetAlpha(0)
	end
	state.suppressed = true
end

local function RestoreRoundedDebuffBorder(borderFrame)
	local state = GetDebuffBorderState(borderFrame, false)
	if not state or not state.suppressed then
		return
	end

	for _, regionState in ipairs(state.regionStates or {}) do
		RestoreRegionVisualState(regionState)
	end
	if state.frameAlpha ~= nil and type(borderFrame.SetAlpha) == "function" then
		borderFrame:SetAlpha(state.frameAlpha)
	end
	state.regionStates = {}
	state.frameAlpha = nil
	state.suppressed = false
end

function TrackedBuffSkin:GetBorderColorOverride(itemFrame)
	if not self:IsTrackedBuffItem(itemFrame) then
		return nil
	end

	local pandemicFrame = GetTrackedBuffPandemicFrame(itemFrame)
	if pandemicFrame then
		EnsurePandemicFrameHooks(pandemicFrame, itemFrame)
		if type(pandemicFrame.IsShown) == "function" and pandemicFrame:IsShown() then
			SetPandemicArtSuppressed(pandemicFrame, true)
			return PANDEMIC_BORDER_COLOR
		end
	end

	local debuffBorder = GetTrackedBuffDebuffBorder(itemFrame)
	if not debuffBorder then
		return nil
	end

	EnsureDebuffBorderHooks(debuffBorder, itemFrame)

	if type(debuffBorder.IsShown) == "function" and debuffBorder:IsShown() then
		SuppressRoundedDebuffBorder(debuffBorder)
		return ResolveBorderColor(debuffBorder, FindVisibleDebuffRegion(debuffBorder))
	end

	return nil
end

function TrackedBuffSkin:ResetBorderStyle(itemFrame)
	if not self:IsTrackedBuffItem(itemFrame) then
		return
	end

	local pandemicFrame = GetTrackedBuffPandemicFrame(itemFrame)
	if pandemicFrame then
		EnsurePandemicFrameHooks(pandemicFrame, itemFrame)
		SetPandemicArtSuppressed(pandemicFrame, false)
	end

	local debuffBorder = GetTrackedBuffDebuffBorder(itemFrame)
	if not debuffBorder then
		return
	end

	EnsureDebuffBorderHooks(debuffBorder, itemFrame)

	RestoreRoundedDebuffBorder(debuffBorder)
end

function TrackedBuffSkin:RefreshViewerPandemicFrames(viewer)
	if not IsUnifiedSkinEnabled() or not IsTrackedBuffIconViewer(viewer) then
		return
	end

	if not viewer or not viewer.itemFramePool or type(viewer.itemFramePool.EnumerateActive) ~= "function" then
		return
	end

	for itemFrame in viewer.itemFramePool:EnumerateActive() do
		local pandemicFrame = GetTrackedBuffPandemicFrame(itemFrame)
		if pandemicFrame and pandemicFrame.IsShown and pandemicFrame:IsShown() then
			EnsurePandemicFrameHooks(pandemicFrame, itemFrame)
			if self.restyleTrackedBuffItem then
				self.restyleTrackedBuffItem(itemFrame)
			end
		end
	end
end

function TrackedBuffSkin:InstallHooks(applyToCooldownViewerItem)
	if self.hooksInstalled or type(hooksecurefunc) ~= "function" then
		return
	end

	self.restyleTrackedBuffItem = applyToCooldownViewerItem

	if CooldownViewerBuffIconItemMixin and type(CooldownViewerBuffIconItemMixin.RefreshData) == "function" then
		hooksecurefunc(CooldownViewerBuffIconItemMixin, "RefreshData", function(itemFrame)
			applyToCooldownViewerItem(itemFrame)
		end)
	end

	if CooldownViewerBuffBarItemMixin and type(CooldownViewerBuffBarItemMixin.RefreshData) == "function" then
		hooksecurefunc(CooldownViewerBuffBarItemMixin, "RefreshData", function(itemFrame)
			applyToCooldownViewerItem(itemFrame)
		end)
	end

	if CooldownViewerItemMixin and type(CooldownViewerItemMixin.RefreshIconBorder) == "function" then
		hooksecurefunc(CooldownViewerItemMixin, "RefreshIconBorder", function(itemFrame)
			applyToCooldownViewerItem(itemFrame)
		end)
	end

	if CooldownViewerItemDebuffBorderMixin and type(CooldownViewerItemDebuffBorderMixin.UpdateFromAuraData) == "function" then
		hooksecurefunc(CooldownViewerItemDebuffBorderMixin, "UpdateFromAuraData", function(borderFrame)
			local itemFrame = ResolveItemFrameFromBorderFrame(borderFrame)
			if itemFrame then
				applyToCooldownViewerItem(itemFrame)
			end
		end)
	end

	if CooldownViewerItemDebuffBorderMixin and type(CooldownViewerItemDebuffBorderMixin.Show) == "function" then
		hooksecurefunc(CooldownViewerItemDebuffBorderMixin, "Show", function(borderFrame)
			local itemFrame = ResolveItemFrameFromBorderFrame(borderFrame)
			if itemFrame then
				applyToCooldownViewerItem(itemFrame)
			end
		end)
	end

	if CooldownViewerItemDebuffBorderMixin and type(CooldownViewerItemDebuffBorderMixin.Hide) == "function" then
		hooksecurefunc(CooldownViewerItemDebuffBorderMixin, "Hide", function(borderFrame)
			local itemFrame = ResolveItemFrameFromBorderFrame(borderFrame)
			if itemFrame then
				applyToCooldownViewerItem(itemFrame)
			end
		end)
	end

	if CooldownViewerItemMixin and type(CooldownViewerItemMixin.ShowPandemicStateFrame) == "function" then
		hooksecurefunc(CooldownViewerItemMixin, "ShowPandemicStateFrame", function(itemFrame)
			if itemFrame and TrackedBuffSkin:IsTrackedBuffIconItem(itemFrame) and itemFrame.PandemicIcon then
				EnsurePandemicFrameHooks(itemFrame.PandemicIcon, itemFrame)
				applyToCooldownViewerItem(itemFrame)
			end
		end)
	end

	if CooldownViewerItemMixin and type(CooldownViewerItemMixin.HidePandemicStateFrame) == "function" then
		hooksecurefunc(CooldownViewerItemMixin, "HidePandemicStateFrame", function(itemFrame)
			if itemFrame and TrackedBuffSkin:IsTrackedBuffIconItem(itemFrame) then
				applyToCooldownViewerItem(itemFrame)
			end
		end)
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.SetupPandemicStateFrameForItem) == "function" then
		hooksecurefunc(CooldownViewerMixin, "SetupPandemicStateFrameForItem", function(viewer, itemFrame)
			if IsTrackedBuffIconViewer(viewer) and itemFrame and itemFrame.PandemicIcon then
				EnsurePandemicFrameHooks(itemFrame.PandemicIcon, itemFrame)
				applyToCooldownViewerItem(itemFrame)
			end
		end)
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.AnchorPandemicStateFrame) == "function" then
		hooksecurefunc(CooldownViewerMixin, "AnchorPandemicStateFrame", function(viewer, pandemicFrame, itemFrame)
			if IsTrackedBuffIconViewer(viewer) and pandemicFrame and itemFrame then
				EnsurePandemicFrameHooks(pandemicFrame, itemFrame)
				applyToCooldownViewerItem(itemFrame)
			end
		end)
	end

	if CooldownViewerMixin and type(CooldownViewerMixin.HidePandemicStateFrame) == "function" then
		hooksecurefunc(CooldownViewerMixin, "HidePandemicStateFrame", function(viewer, pandemicFrame)
			if IsTrackedBuffIconViewer(viewer) and pandemicFrame then
				local itemFrame = ResolveItemFrameFromPandemicFrame(pandemicFrame)
				if itemFrame then
					applyToCooldownViewerItem(itemFrame)
				end
			end
		end)
	end

	self.hooksInstalled = true
end
