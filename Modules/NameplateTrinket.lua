-- Copyright (c) 2026 Bodify. All rights reserved.
-- This file is part of the sArena Reloaded addon (DIY).
-- Mirrors the sArena enemy trinket (PvP CC remover) icon and cooldown
-- onto the enemy nameplate above the arena unit, similar to MidnightDR Arena module.

local isMidnight = sArenaMixin.isMidnight

local function IsForbidden(obj)
    if not obj then return true end
    local ok, res = pcall(function()
        if obj.IsForbidden then return obj:IsForbidden() end
        return false
    end)
    return (not ok) or (res and true or false)
end

local function IsSecret(v)
    if not _G.issecretvalue then return false end
    local ok, r = pcall(_G.issecretvalue, v)
    return ok and r and true or false
end

local function SafeIndex(obj, key)
    if IsForbidden(obj) then return nil end
    local ok, v = pcall(function() return obj[key] end)
    return ok and v or nil
end

local function GetNPTDB(parent)
    if not parent or not parent.db or not parent.db.profile then return nil end
    local d = parent.db.profile.nameplateTrinket
    if not d then
        parent.db.profile.nameplateTrinket = {
            enabled = true,
            shownAs = "always",
            size = 26,
            posX = 0,
            posY = 4,
            fontSize = 14,
            borderSize = 1,
            alpha = 1.0,
        }
        d = parent.db.profile.nameplateTrinket
    end
    return d
end

-- =============================================
-- Mirror frame creation
-- =============================================

function sArenaFrameMixin:CreateNameplateTrinket()
    if self.TrinketNP then return end

    local name = "sArenaEnemyFrame" .. self:GetID() .. "_NPTrinket"
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(26, 26)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(220)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    f.Icon = icon

    local cd = CreateFrame("Cooldown", name .. "CD", f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawBling(false)
    cd:SetReverse(false)
    cd:SetSwipeColor(0, 0, 0, 0.55)
    cd:SetHideCountdownNumbers(false)
    f.Cooldown = cd

    local cdText = nil
    if cd.GetRegions then
        for _, region in next, { cd:GetRegions() } do
            if region:GetObjectType() == "FontString" then
                cdText = region; break
            end
        end
    end
    if not cdText and cd.GetCountdownFontString then
        cdText = cd:GetCountdownFontString()
    end
    f.CDText = cdText

    local borderFrame = CreateFrame("Frame", nil, f)
    borderFrame:SetPoint("TOPLEFT", -1, 1)
    borderFrame:SetPoint("BOTTOMRIGHT", 1, -1)
    borderFrame:SetFrameLevel(f:GetFrameLevel() + 2)
    local function makeLine()
        local t = borderFrame:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 0.82, 0, 1)
        return t
    end
    local bTop = makeLine(); bTop:SetHeight(1); bTop:SetPoint("TOPLEFT"); bTop:SetPoint("TOPRIGHT")
    local bBot = makeLine(); bBot:SetHeight(1); bBot:SetPoint("BOTTOMLEFT"); bBot:SetPoint("BOTTOMRIGHT")
    local bLeft = makeLine(); bLeft:SetWidth(1); bLeft:SetPoint("TOPLEFT"); bLeft:SetPoint("BOTTOMLEFT")
    local bRight = makeLine(); bRight:SetWidth(1); bRight:SetPoint("TOPRIGHT"); bRight:SetPoint("BOTTOMRIGHT")
    f.BorderTextures = { bTop, bBot, bLeft, bRight }

    self.TrinketNP = f

    self:InstallNameplateTrinketHooks()
end

-- =============================================
-- Source hook strategy (mirrors MidnightDR/Arena.lua HookTrinket):
-- Hook the Blizzard-native CompactArenaFrameMember{i}.CcRemoverFrame directly,
-- NOT the sArena.Trinket wrapper. This bypasses sArena's colorTrinket / desaturate
-- transforms and is the same proven path MidnightDR uses.
-- =============================================

local function GetBlizzCcRemoverFrame(arenaIndex)
    local member = _G["CompactArenaFrameMember" .. arenaIndex]
    if not member or IsForbidden(member) then return nil end
    local src = SafeIndex(member, "CcRemoverFrame")
    if not src or IsForbidden(src) then return nil end
    return src
end

function sArenaFrameMixin:InstallNameplateTrinketHooks()
    if self._npTrinketHooked then return end

    local idx = self:GetID()
    local src = GetBlizzCcRemoverFrame(idx)
    if not src then return end

    local icon = SafeIndex(src, "Icon") or SafeIndex(src, "icon")
    if icon and IsForbidden(icon) then icon = nil end
    local cd = SafeIndex(src, "Cooldown") or SafeIndex(src, "cooldown") or SafeIndex(src, "CooldownFrame")
    if cd and IsForbidden(cd) then cd = nil end
    if not icon or not cd then return end

    self._npTrinketHooked = true
    self._npTrinketSrc = src
    self._npTrinketUnit = "arena" .. idx

    local arenaFrame = self

    -- Initial copy of current source texture (if any), to bootstrap mirror.
    pcall(function()
        local t = icon.GetTexture and icon:GetTexture() or nil
        if t ~= nil then
            if not IsSecret(t) then
                if t == 0 or t == "" then return end
            end
            if arenaFrame.SyncNameplateTrinketTexture then
                arenaFrame:SyncNameplateTrinketTexture(t)
            end
        end
    end)

    pcall(function()
        hooksecurefunc(icon, "SetTexture", function(_, tex)
            if tex == nil then return end
            if not IsSecret(tex) then
                if tex == 0 or tex == "" then return end
            end
            if arenaFrame.SyncNameplateTrinketTexture then
                arenaFrame:SyncNameplateTrinketTexture(tex)
            end
        end)
    end)

    pcall(function()
        hooksecurefunc(cd, "SetCooldown", function(_, start, duration)
            if arenaFrame.SyncNameplateTrinketCooldownFromBlizz then
                arenaFrame:SyncNameplateTrinketCooldownFromBlizz(start, duration)
            end
        end)
    end)

    pcall(function()
        cd:HookScript("OnCooldownDone", function()
            arenaFrame._npTrinketCDActive = false
            if arenaFrame.UpdateNameplateTrinketPosition then
                arenaFrame:UpdateNameplateTrinketPosition()
            end
        end)
    end)
end

-- =============================================
-- Sync handlers
-- =============================================

function sArenaFrameMixin:SyncNameplateTrinketTexture(tex)
    if not self.TrinketNP or not self.TrinketNP.Icon then return end
    if tex == nil then
        self.TrinketNP.Icon:SetTexture(nil)
        self:UpdateNameplateTrinketPosition()
        return
    end

    self.TrinketNP.Icon:SetTexture(tex)
    self.TrinketNP.Icon:SetDesaturated(false)
    self.TrinketNP.Icon:SetVertexColor(1, 1, 1, 1)
    self:UpdateNameplateTrinketPosition()
end

-- Cooldown sync, mirroring MidnightDR/Arena.lua HookTrinket inner logic exactly:
-- when Blizzard's CcRemoverFrame.Cooldown:SetCooldown fires we pull the canonical
-- DurationObject from C_PvP.GetArenaCrowdControlDuration(unit) and apply that to
-- the mirror cooldown; falling back to the raw (start, duration) tuple if needed.
function sArenaFrameMixin:SyncNameplateTrinketCooldownFromBlizz(start, duration)
    if not self.TrinketNP or not self.TrinketNP.Cooldown then return end

    local clear = false
    if duration == nil then
        clear = true
    elseif not IsSecret(duration) then
        local d = tonumber(duration)
        if not d or d <= 0 then clear = true end
    end

    if clear then
        self.TrinketNP.Cooldown:SetCooldown(0, 0)
        self.TrinketNP.Cooldown:Clear()
        self._npTrinketCDActive = false
        self:UpdateNameplateTrinketPosition()
        return
    end

    local unit = self._npTrinketUnit or ("arena" .. self:GetID())
    local usedDurationObject = false
    if C_PvP and C_PvP.GetArenaCrowdControlDuration and self.TrinketNP.Cooldown.SetCooldownFromDurationObject then
        local okObj, durationObj = pcall(C_PvP.GetArenaCrowdControlDuration, unit)
        if okObj and durationObj then
            local okSet = pcall(function()
                self.TrinketNP.Cooldown:SetCooldownFromDurationObject(durationObj)
            end)
            usedDurationObject = okSet and true or false
        end
    end

    if not usedDurationObject then
        local s = tonumber(start) or 0
        local d = tonumber(duration) or 0
        if s > 0 and d > 0 then
            self.TrinketNP.Cooldown:SetCooldown(s, d)
        end
    end

    self._npTrinketCDActive = true
    self:UpdateNameplateTrinketPosition()
end

function sArenaFrameMixin:HideNameplateTrinket()
    if not self.TrinketNP then return end
    self.TrinketNP:Hide()
end

-- =============================================
-- Position / show logic
-- =============================================

function sArenaFrameMixin:UpdateNameplateTrinketPosition()
    if not self.TrinketNP then return end

    local db = GetNPTDB(self.parent)
    if not db or not db.enabled then
        self.TrinketNP:Hide()
        return
    end

    local _, instanceType = IsInInstance()
    if instanceType ~= "arena" then
        self.TrinketNP:Hide()
        return
    end

    -- The trinket data source is Blizzard's CcRemoverFrame (mirroring MidnightDR).
    -- Visibility is gated purely by whether the mirror Icon currently has a texture -
    -- no spellID-based guard, no sArena-internal Trinket field dependency.
    local hasIcon = false
    if self.TrinketNP.Icon and self.TrinketNP.Icon.GetTexture then
        local ok, t = pcall(function() return self.TrinketNP.Icon:GetTexture() end)
        if ok and t then hasIcon = true end
    end
    if not hasIcon then
        self.TrinketNP:Hide()
        return
    end

    local shownAs = db.shownAs or "always"
    if shownAs == "used" and not self._npTrinketCDActive then
        self.TrinketNP:Hide()
        return
    end

    local arenaUnit = "arena" .. self:GetID()
    local anchor = self.parent.GetNameplateAnchorForArena and self.parent:GetNameplateAnchorForArena(arenaUnit)
    if not anchor or IsForbidden(anchor) then
        self.TrinketNP:Hide()
        return
    end

    local size = db.size or 26
    local posX = db.posX or 0
    local posY = db.posY or 4
    local fontSize = db.fontSize or 14
    local borderSize = db.borderSize or 1
    local alpha = db.alpha or 1.0

    local us = (anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or 1
    local ps = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local sc = us / ps
    if sc < 0.1 then sc = 0.1 elseif sc > 10 then sc = 10 end

    local f = self.TrinketNP
    f:SetSize(size, size)
    f:SetScale(sc)
    f:SetAlpha(alpha)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", anchor, "TOP", posX, posY)

    if f.BorderTextures then
        for _, tex in ipairs(f.BorderTextures) do
            tex:SetHeight(borderSize)
            tex:SetWidth(borderSize)
        end
    end

    if f.CDText then
        local fontFile = f.CDText.fontFile or select(1, f.CDText:GetFont())
        local flags = f.CDText.fontFlags or select(3, f.CDText:GetFont())
        if fontFile then
            pcall(function() f.CDText:SetFont(fontFile, fontSize, flags or "OUTLINE") end)
        end
    end

    f:Show()
end

-- =============================================
-- Manager methods on sArenaMixin
-- =============================================

function sArenaMixin:UpdateNameplateTrinketSettings(info, val)
    if val ~= nil and info then
        self.db.profile.nameplateTrinket = self.db.profile.nameplateTrinket or {}
        self.db.profile.nameplateTrinket[info[#info]] = val
    end

    if self.testMode then
        self:ShowTestNameplateTrinket()
    else
        self:RefreshAllNameplateTrinket()
    end
end

function sArenaMixin:RefreshAllNameplateTrinket()
    for i = 1, self.maxArenaOpponents do
        local frame = self["arena" .. i]
        if frame then
            if not frame.TrinketNP then
                frame:CreateNameplateTrinket()
            end
            -- Retry hook installation if it didn't take the first time
            -- (Blizzard CompactArenaFrameMember{i} may not be ready until arena init)
            if not frame._npTrinketHooked and frame.InstallNameplateTrinketHooks then
                frame:InstallNameplateTrinketHooks()
            end
            frame:UpdateNameplateTrinketPosition()
        end
    end
end

function sArenaMixin:HideAllNameplateTrinket()
    for i = 1, self.maxArenaOpponents do
        local frame = self["arena" .. i]
        if frame and frame.TrinketNP then
            frame.TrinketNP:Hide()
        end
    end
end

-- =============================================
-- Test mode
-- =============================================

function sArenaMixin:ShowTestNameplateTrinket()
    local db = GetNPTDB(self)
    if not db or not db.enabled then return end

    local anchor = self.GetBestTestNameplate and self:GetBestTestNameplate()
    if not anchor then return end

    local frame = self.arena1
    if not frame then return end
    if not frame.TrinketNP then frame:CreateNameplateTrinket() end

    local size = db.size or 26
    local posX = db.posX or 0
    local posY = db.posY or 4
    local fontSize = db.fontSize or 14
    local borderSize = db.borderSize or 1
    local alpha = db.alpha or 1.0

    local us = (anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or 1
    local ps = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local sc = us / ps
    if sc < 0.1 then sc = 0.1 elseif sc > 10 then sc = 10 end

    local f = frame.TrinketNP
    f:SetSize(size, size)
    f:SetScale(sc)
    f:SetAlpha(alpha)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", anchor, "TOP", posX, posY)

    local testTex = self.trinketTexture or 1322720
    f.Icon:SetTexture(testTex)
    f.Icon:SetDesaturated(false)
    f.Cooldown:SetCooldown(GetTime(), 120)

    if f.BorderTextures then
        for _, tex in ipairs(f.BorderTextures) do
            tex:SetHeight(borderSize)
            tex:SetWidth(borderSize)
        end
    end

    if f.CDText then
        local fontFile = f.CDText.fontFile or select(1, f.CDText:GetFont())
        local flags = f.CDText.fontFlags or select(3, f.CDText:GetFont())
        if fontFile then
            pcall(function() f.CDText:SetFont(fontFile, fontSize, flags or "OUTLINE") end)
        end
    end

    f:Show()
end

function sArenaMixin:HideTestNameplateTrinket()
    self:HideAllNameplateTrinket()
end
