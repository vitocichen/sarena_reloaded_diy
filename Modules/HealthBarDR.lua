local isMidnight = sArenaMixin.isMidnight
local MAX_NP_DR_SLOTS = 7

-- Nameplate DR mirror system: shows DR icons anchored to enemy nameplates

-- =============================================
-- Safe helpers (Midnight secret value protection)
-- =============================================

local function IsSecret(v)
    if not issecretvalue then return false end
    local ok, r = pcall(issecretvalue, v)
    return ok and r and true or false
end

local function IsForbidden(obj)
    if not obj then return true end
    local ok, res = pcall(function()
        if obj.IsForbidden then return obj:IsForbidden() end
        return false
    end)
    return (not ok) or (res and true or false)
end

local function SafeIndex(obj, key)
    if IsForbidden(obj) then return nil end
    local ok, v = pcall(function() return obj[key] end)
    return ok and v or nil
end

local function SafeUnitGUID(unit)
    local ok, g = pcall(UnitGUID, unit)
    if not ok or type(g) ~= "string" or IsSecret(g) then return nil end
    return g
end

local function SafeUnitExists(unit)
    local ok, r = pcall(UnitExists, unit)
    if not ok or type(r) ~= "boolean" or IsSecret(r) then return false end
    return r
end

local function SafeUnitIsUnit(a, b)
    local ok, r = pcall(UnitIsUnit, a, b)
    if not ok or type(r) ~= "boolean" or IsSecret(r) then return nil end
    return r
end

local function SafeUnitClassToken(unit)
    local ok, _, classToken = pcall(UnitClass, unit)
    if not ok or type(classToken) ~= "string" or IsSecret(classToken) then return nil end
    return classToken
end

local function SafeUnitRaceName(unit)
    local ok, raceName = pcall(UnitRace, unit)
    if not ok or type(raceName) ~= "string" or IsSecret(raceName) then return nil end
    return raceName
end

local function SafeUnitHonorLevel(unit)
    if not UnitHonorLevel then return 0 end
    local ok, h = pcall(UnitHonorLevel, unit)
    if not ok or type(h) ~= "number" or IsSecret(h) then return 0 end
    return h
end

-- =============================================
-- Nameplate matching (adapted from MidnightDR)
-- =============================================

local npAnchorCache = {}
local npTokenToArena = {}

local function PlateToken(np)
    local tok = SafeIndex(np, "namePlateUnitToken")
    if tok then return tok end
    local uf = SafeIndex(np, "UnitFrame")
    return uf and SafeIndex(uf, "unit") or nil
end

local function BuildCompositeKey(unit)
    local classToken = SafeUnitClassToken(unit)
    local raceName = SafeUnitRaceName(unit)
    if not classToken or not raceName then return nil end
    local honor = SafeUnitHonorLevel(unit)
    local ok, key = pcall(string.format, "%d:%s:%s", honor, classToken, raceName)
    return ok and key or nil
end

local function CacheValid(arenaUnit, plates)
    local c = npAnchorCache[arenaUnit]
    if not c or not c.token or not c.anchor or IsForbidden(c.anchor) then return nil end
    if not SafeUnitExists(c.token) then
        npTokenToArena[c.token] = nil
        npAnchorCache[arenaUnit] = nil
        return nil
    end
    for _, np in ipairs(plates) do
        if np and not IsForbidden(np) then
            if PlateToken(np) == c.token then
                local a = SafeIndex(np, "UnitFrame") or np
                c.anchor = a
                return a
            end
        end
    end
    npTokenToArena[c.token] = nil
    npAnchorCache[arenaUnit] = nil
    return nil
end

local function CacheBind(arenaUnit, token, anchor)
    if not arenaUnit or not token or not anchor then return end
    local old = npAnchorCache[arenaUnit]
    if old and old.token and old.token ~= token then
        npTokenToArena[old.token] = nil
    end
    npAnchorCache[arenaUnit] = { token = token, anchor = anchor }
    npTokenToArena[token] = arenaUnit
end

local function TryMatchArenaToPlate(unit, plates)
    local arenaGUID = SafeUnitGUID(unit)
    if arenaGUID then
        for _, np in ipairs(plates) do
            if np and not IsForbidden(np) then
                local tok = PlateToken(np)
                if tok and SafeUnitExists(tok) then
                    local g = SafeUnitGUID(tok)
                    if g and g == arenaGUID then
                        return tok, SafeIndex(np, "UnitFrame") or np
                    end
                end
            end
        end
    end

    local arenaKey = BuildCompositeKey(unit)
    if arenaKey then
        local used = {}
        for _, c in pairs(npAnchorCache) do
            if c.token then used[c.token] = true end
        end
        for _, np in ipairs(plates) do
            if np and not IsForbidden(np) then
                local tok = PlateToken(np)
                if tok and not used[tok] and SafeUnitExists(tok) then
                    local k = BuildCompositeKey(tok)
                    if k and k == arenaKey then
                        return tok, SafeIndex(np, "UnitFrame") or np
                    end
                end
            end
        end
    end

    return nil
end

function sArenaMixin:GetNameplateAnchorForArena(unit)
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or not plates then return nil end

    local cached = CacheValid(unit, plates)
    if cached then return cached end

    local tok, anchor = TryMatchArenaToPlate(unit, plates)
    if tok and anchor then
        CacheBind(unit, tok, anchor)
        return anchor
    end

    local function BridgeMatch(bridge)
        if not SafeUnitExists(bridge) then return false end
        return SafeUnitIsUnit(bridge, unit) == true or SafeUnitIsUnit(unit, bridge) == true
    end

    local bridgeUnit
    if BridgeMatch("target") then bridgeUnit = "target"
    elseif BridgeMatch("focus") then bridgeUnit = "focus"
    elseif BridgeMatch("mouseover") then bridgeUnit = "mouseover" end

    if bridgeUnit then
        for _, np in ipairs(plates) do
            if np and not IsForbidden(np) then
                local tok2 = PlateToken(np)
                if tok2 then
                    local r = SafeUnitIsUnit(tok2, bridgeUnit)
                    if r == true then
                        local a = SafeIndex(np, "UnitFrame") or np
                        CacheBind(unit, tok2, a)
                        return a
                    end
                end
            end
        end
    end

    return nil
end

function sArenaMixin:ClearNameplateAnchorCache(token)
    if token then
        local au = npTokenToArena[token]
        if au then npAnchorCache[au] = nil end
        npTokenToArena[token] = nil
    end
end

function sArenaMixin:ClearAllNameplateAnchors()
    wipe(npAnchorCache)
    wipe(npTokenToArena)
end

-- =============================================
-- Nameplate DR mirror frames
-- =============================================

function sArenaFrameMixin:CreateNameplateDRFrames()
    if self.drFramesNP then return end
    self.drFramesNP = {}

    local numSlots = isMidnight and (self.drFrames and #self.drFrames or MAX_NP_DR_SLOTS) or #self.parent.drCategories

    for s = 1, numSlots do
        local name = "sArenaEnemyFrame" .. self:GetID() .. "_NPDR" .. s
        local f = CreateFrame("Frame", name, UIParent)
        f:SetSize(22, 22)
        f:SetFrameStrata("HIGH")
        f:SetFrameLevel(200)
        f:Hide()

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        f.Icon = icon

        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.7)

        local cd = CreateFrame("Cooldown", name .. "CD", f, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawBling(false)
        cd:SetReverse(true)
        cd:SetSwipeColor(0, 0, 0, 0.6)
        f.Cooldown = cd

        local borderFrame = CreateFrame("Frame", nil, f)
        borderFrame:SetPoint("TOPLEFT", -1, 1)
        borderFrame:SetPoint("BOTTOMRIGHT", 1, -1)
        borderFrame:SetFrameLevel(f:GetFrameLevel() + 2)
        local bTop = borderFrame:CreateTexture(nil, "OVERLAY")
        bTop:SetHeight(1); bTop:SetPoint("TOPLEFT"); bTop:SetPoint("TOPRIGHT"); bTop:SetColorTexture(0, 1, 0, 1)
        local bBot = borderFrame:CreateTexture(nil, "OVERLAY")
        bBot:SetHeight(1); bBot:SetPoint("BOTTOMLEFT"); bBot:SetPoint("BOTTOMRIGHT"); bBot:SetColorTexture(0, 1, 0, 1)
        local bLeft = borderFrame:CreateTexture(nil, "OVERLAY")
        bLeft:SetWidth(1); bLeft:SetPoint("TOPLEFT"); bLeft:SetPoint("BOTTOMLEFT"); bLeft:SetColorTexture(0, 1, 0, 1)
        local bRight = borderFrame:CreateTexture(nil, "OVERLAY")
        bRight:SetWidth(1); bRight:SetPoint("TOPRIGHT"); bRight:SetPoint("BOTTOMRIGHT"); bRight:SetColorTexture(0, 1, 0, 1)
        f.BorderTextures = { bTop, bBot, bLeft, bRight }

        local textHolder = CreateFrame("Frame", nil, f)
        textHolder:SetAllPoints()
        textHolder:SetFrameLevel(cd:GetFrameLevel() + 3)
        f.CDText = textHolder:CreateFontString(nil, "OVERLAY")
        f.CDText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        f.CDText:SetPoint("CENTER", 0, 0)
        f.CDText:SetTextColor(1, 1, 1, 1)

        f.GlowTexture = f:CreateTexture(nil, "OVERLAY", nil, 7)
        f.GlowTexture:SetPoint("TOPLEFT", -3, 3)
        f.GlowTexture:SetPoint("BOTTOMRIGHT", 3, -3)
        f.GlowTexture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        f.GlowTexture:SetBlendMode("ADD")
        f.GlowTexture:SetAlpha(0)

        self.drFramesNP[s] = f
    end
end

function sArenaFrameMixin:SetNameplateDRBorderColor(slot, r, g, b, a)
    local f = self.drFramesNP and self.drFramesNP[slot]
    if not f or not f.BorderTextures then return end
    for _, tex in ipairs(f.BorderTextures) do
        tex:SetColorTexture(r, g, b, a or 1)
    end
end

function sArenaFrameMixin:SetNameplateDRGlow(slot, enabled, r, g, b)
    if not self.drFramesNP then return end
    local f = self.drFramesNP[slot]
    if not f or not f.GlowTexture then return end

    if enabled then
        f.GlowTexture:SetVertexColor(r or 1, g or 0, b or 0)
        f.GlowTexture:SetAlpha(0.8)
        if not f.glowAnim then
            local ag = f.GlowTexture:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local fade = ag:CreateAnimation("Alpha")
            fade:SetFromAlpha(0.8)
            fade:SetToAlpha(0.3)
            fade:SetDuration(0.6)
            fade:SetSmoothing("IN_OUT")
            f.glowAnim = ag
        end
        f.glowAnim:Play()
    else
        if f.glowAnim then f.glowAnim:Stop() end
        f.GlowTexture:SetAlpha(0)
    end
end

function sArenaFrameMixin:HideAllNameplateDR()
    if not self.drFramesNP then return end
    for _, f in ipairs(self.drFramesNP) do
        f.Icon:SetTexture(nil)
        f.Cooldown:Clear()
        f:Hide()
    end
end

function sArenaFrameMixin:UpdateNameplateDRPositions()
    if not self.drFramesNP then return end

    local layoutdb = self.parent.layoutdb
    if not layoutdb or not layoutdb.drNameplate then return end

    local db = layoutdb.drNameplate
    local size = db.size or 22
    local spacing = db.spacing or 2
    local grow = db.growthDirection or 3
    local posX = db.posX or 0
    local posY = db.posY or 0

    local arenaUnit = "arena" .. self:GetID()
    local anchor = self.parent:GetNameplateAnchorForArena(arenaUnit)

    if not anchor or IsForbidden(anchor) then
        for _, f in ipairs(self.drFramesNP) do f:Hide() end
        return
    end

    local us = (anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or 1
    local ps = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local sc = us / ps
    if sc < 0.1 then sc = 0.1 elseif sc > 10 then sc = 10 end

    local fontSize = db.fontSize or 12

    local numActive = 0
    local prevFrame
    for _, f in ipairs(self.drFramesNP) do
        f:SetSize(size, size)
        f:SetScale(sc)
        if f.CDText then
            f.CDText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
        end
        if f:IsShown() then
            f:ClearAllPoints()
            if numActive == 0 then
                if grow == 4 then
                    f:SetPoint("RIGHT", anchor, "CENTER", posX, posY)
                elseif grow == 3 then
                    f:SetPoint("LEFT", anchor, "CENTER", posX, posY)
                elseif grow == 1 then
                    f:SetPoint("TOP", anchor, "CENTER", posX, posY)
                elseif grow == 2 then
                    f:SetPoint("BOTTOM", anchor, "CENTER", posX, posY)
                end
            else
                if grow == 4 then
                    f:SetPoint("RIGHT", prevFrame, "LEFT", -spacing, 0)
                elseif grow == 3 then
                    f:SetPoint("LEFT", prevFrame, "RIGHT", spacing, 0)
                elseif grow == 1 then
                    f:SetPoint("TOP", prevFrame, "BOTTOM", 0, -spacing)
                elseif grow == 2 then
                    f:SetPoint("BOTTOM", prevFrame, "TOP", 0, spacing)
                end
            end
            numActive = numActive + 1
            prevFrame = f
        end
    end
end

function sArenaMixin:UpdateNameplateDRSettings(db, info, val)
    if val ~= nil and info then
        db[info[#info]] = val
    end
    if not db then return end

    if self.testMode then
        self:ShowTestNameplateDR()
    else
        for i = 1, self.maxArenaOpponents do
            local frame = self["arena" .. i]
            if frame then
                if not frame.drFramesNP then
                    frame:CreateNameplateDRFrames()
                end
                frame:UpdateNameplateDRPositions()
            end
        end
    end
end

function sArenaMixin:RefreshAllNameplateDR()
    for i = 1, self.maxArenaOpponents do
        local frame = self["arena" .. i]
        if frame and frame.drFramesNP then
            frame:UpdateNameplateDRPositions()
        end
    end
end

function sArenaMixin:GetBestTestNameplate()
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or not plates then return nil end

    for _, unit in ipairs({"target", "mouseover"}) do
        if SafeUnitExists(unit) then
            for _, np in ipairs(plates) do
                if np and not IsForbidden(np) then
                    local tok = PlateToken(np)
                    if tok then
                        local r = SafeUnitIsUnit(tok, unit)
                        if r == true then
                            return SafeIndex(np, "UnitFrame") or np
                        end
                    end
                end
            end
        end
    end

    for _, np in ipairs(plates) do
        if np and not IsForbidden(np) then
            local uf = SafeIndex(np, "UnitFrame") or np
            if uf and not IsForbidden(uf) then
                local shownOk, shown = pcall(function() return uf:IsShown() end)
                if shownOk and shown then return uf end
            end
        end
    end
    return nil
end

function sArenaMixin:ShowTestNameplateDR()
    local layoutdb = self.layoutdb
    if not layoutdb or not layoutdb.drNameplate then return end

    local anchor = self:GetBestTestNameplate()
    if not anchor then return end

    local db = layoutdb.drNameplate
    local size = db.size or 22
    local spacing = db.spacing or 2
    local grow = db.growthDirection or 3
    local posX = db.posX or 0
    local posY = db.posY or 0

    local us = (anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or 1
    local ps = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local sc = us / ps
    if sc < 0.1 then sc = 0.1 elseif sc > 10 then sc = 10 end

    local testTextures = { 136071, 132298, 136100, 136183 }
    local testColors = { {1,0,0}, {0,1,0}, {0,1,0}, {0,1,0} }
    local now = GetTime()

    local frame = self.arena1
    if not frame then return end
    if not frame.drFramesNP then frame:CreateNameplateDRFrames() end

    local prevFrame
    for n = 1, math.min(4, #frame.drFramesNP) do
        local f = frame.drFramesNP[n]
        if f then
            f:SetParent(UIParent)
            f:SetSize(size, size)
            f:SetScale(sc)
            f:ClearAllPoints()

            if n == 1 then
                if grow == 4 then
                    f:SetPoint("RIGHT", anchor, "CENTER", posX, posY)
                elseif grow == 3 then
                    f:SetPoint("LEFT", anchor, "CENTER", posX, posY)
                elseif grow == 1 then
                    f:SetPoint("TOP", anchor, "CENTER", posX, posY)
                else
                    f:SetPoint("BOTTOM", anchor, "CENTER", posX, posY)
                end
            else
                if grow == 4 then
                    f:SetPoint("RIGHT", prevFrame, "LEFT", -spacing, 0)
                elseif grow == 3 then
                    f:SetPoint("LEFT", prevFrame, "RIGHT", spacing, 0)
                elseif grow == 1 then
                    f:SetPoint("TOP", prevFrame, "BOTTOM", 0, -spacing)
                else
                    f:SetPoint("BOTTOM", prevFrame, "TOP", 0, spacing)
                end
            end

            f.Icon:SetTexture(testTextures[n])
            f.Cooldown:SetCooldown(now, math.random(12, 30))
            frame:SetNameplateDRBorderColor(n, testColors[n][1], testColors[n][2], testColors[n][3])
            f:Show()
            prevFrame = f
        end
    end
end

function sArenaMixin:HideTestNameplateDR()
    local frame = self.arena1
    if frame and frame.drFramesNP then
        frame:HideAllNameplateDR()
    end
end

-- =============================================
-- Healthbar Trinket Mirror
-- =============================================

function sArenaFrameMixin:CreateHealthBarTrinket()
    if self.TrinketHB then return end

    local name = "sArenaEnemyFrame" .. self:GetID() .. "_HBTrinket"
    local f = CreateFrame("Frame", name, self)
    f:SetSize(20, 20)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(self:GetFrameLevel() + 12)
    f:Hide()

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    f.Icon = icon

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)

    local cd = CreateFrame("Cooldown", name .. "CD", f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawBling(false)
    cd:SetReverse(false)
    cd:SetSwipeColor(0, 0, 0, 0.6)
    f.Cooldown = cd

    local borderFrame = CreateFrame("Frame", nil, f)
    borderFrame:SetPoint("TOPLEFT", -1, 1)
    borderFrame:SetPoint("BOTTOMRIGHT", 1, -1)
    borderFrame:SetFrameLevel(f:GetFrameLevel() + 2)
    local bTop = borderFrame:CreateTexture(nil, "OVERLAY")
    bTop:SetHeight(1); bTop:SetPoint("TOPLEFT"); bTop:SetPoint("TOPRIGHT"); bTop:SetColorTexture(1, 1, 0, 1)
    local bBot = borderFrame:CreateTexture(nil, "OVERLAY")
    bBot:SetHeight(1); bBot:SetPoint("BOTTOMLEFT"); bBot:SetPoint("BOTTOMRIGHT"); bBot:SetColorTexture(1, 1, 0, 1)
    local bLeft = borderFrame:CreateTexture(nil, "OVERLAY")
    bLeft:SetWidth(1); bLeft:SetPoint("TOPLEFT"); bLeft:SetPoint("BOTTOMLEFT"); bLeft:SetColorTexture(1, 1, 0, 1)
    local bRight = borderFrame:CreateTexture(nil, "OVERLAY")
    bRight:SetWidth(1); bRight:SetPoint("TOPRIGHT"); bRight:SetPoint("BOTTOMRIGHT"); bRight:SetColorTexture(1, 1, 0, 1)
    f.BorderTextures = { bTop, bBot, bLeft, bRight }

    self.TrinketHB = f
end

function sArenaFrameMixin:UpdateHealthBarTrinketPosition()
    if not self.TrinketHB then return end

    local db = self.parent.db
    if not db then return end

    local trinketHBSettings = db.profile.trinketOnHealthBar
    if not trinketHBSettings or not trinketHBSettings.enabled then
        self.TrinketHB:Hide()
        return
    end

    local size = trinketHBSettings.size or 20
    self.TrinketHB:SetSize(size, size)
    self.TrinketHB:ClearAllPoints()
    self.TrinketHB:SetPoint("LEFT", self.HealthBar, "RIGHT", (trinketHBSettings.posX or 0) + 2, trinketHBSettings.posY or 0)
end

function sArenaMixin:UpdateHealthBarTrinketSettings(info, val)
    if val ~= nil and info then
        self.db.profile.trinketOnHealthBar[info[#info]] = val
    end

    for i = 1, self.maxArenaOpponents do
        local frame = self["arena" .. i]
        if frame then
            if not frame.TrinketHB then
                frame:CreateHealthBarTrinket()
            end
            frame:UpdateHealthBarTrinketPosition()
        end
    end
end
