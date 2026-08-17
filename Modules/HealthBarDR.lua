local isMidnight = sArenaMixin.isMidnight
local MAX_NP_DR_SLOTS = 7

local function GetSArenaFrame()
    return _G["sArena"]
end

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

local function SafeSecureCall(fn, ...)
    if type(_G.securecallfunction) == "function" then
        local ok, a, b, c, d, e = pcall(_G.securecallfunction, fn, ...)
        if ok then return true, a, b, c, d, e end
        return false
    end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return true, a, b, c, d, e end
    return false
end

local function SafeCloneString(s)
    if type(s) ~= "string" then return nil end
    if IsSecret(s) then return nil end
    local ok, out = pcall(string.format, "%s", s)
    if not ok or type(out) ~= "string" then return nil end
    return out
end

local function SafeUnitClassToken(unit)
    if type(_G.UnitClass) ~= "function" then return nil end
    local ok, _, classToken = SafeSecureCall(_G.UnitClass, unit)
    if not ok then return nil end
    return SafeCloneString(classToken)
end

local function SafeUnitRaceName(unit)
    if type(_G.UnitRace) ~= "function" then return nil end
    local ok, raceName = SafeSecureCall(_G.UnitRace, unit)
    if not ok then return nil end
    return SafeCloneString(raceName)
end

local function SafeUnitHonorLevel(unit)
    if type(_G.UnitHonorLevel) ~= "function" then return nil end
    local ok, honorLevel = SafeSecureCall(_G.UnitHonorLevel, unit)
    if not ok or type(honorLevel) ~= "number" or IsSecret(honorLevel) then return nil end
    local okMath, n = pcall(function() return honorLevel + 0 end)
    if not okMath or type(n) ~= "number" then return nil end
    return n
end

local function SafeUnitIsEnemy(a, b)
    if type(_G.UnitIsEnemy) ~= "function" then return nil end
    local ok, r = pcall(_G.UnitIsEnemy, a, b)
    if not ok or type(r) ~= "boolean" or IsSecret(r) then return nil end
    return r
end

local function SafeUnitIsPlayer(unit)
    if type(_G.UnitIsPlayer) ~= "function" then return nil end
    local ok, r = pcall(_G.UnitIsPlayer, unit)
    if not ok or type(r) ~= "boolean" or IsSecret(r) then return nil end
    return r
end

-- =============================================
-- Nameplate matching (copied from MidnightDR Arena.lua)
-- =============================================

local npAnchorCache = {}
local npTokenToArena = {}

-- MDR-compatible plate token resolution: try multiple possible field names.
local function PlateToken(np)
    local tok = SafeIndex(np, "namePlateUnitToken")
    if tok then return tok end
    local tok2 = SafeIndex(np, "unitToken")
    if tok2 then return tok2 end
    local uf = SafeIndex(np, "UnitFrame") or SafeIndex(np, "unitFrame")
    tok = uf and SafeIndex(uf, "unit") or nil
    if tok then return tok end
    -- MDR: also check TPFrame as an intermediate
    local tp = SafeIndex(np, "TPFrame")
    if tp then
        tok = SafeIndex(tp, "unit") or SafeIndex(tp, "namePlateUnitToken")
        if tok then return tok end
    end
    return nil
end

-- MDR: determine whether a frame qualifies as a nameplate anchor candidate.
local function IsNameplateAnchorFrame(frame)
    if not frame or IsForbidden(frame) then return false end
    return type(SafeIndex(frame, "SetPoint")) == "function"
       and type(SafeIndex(frame, "GetFrameLevel")) == "function"
end

-- MDR: a candidate resolves through its own GetAnchor() when the client exposes one.
local function ResolveNameplateAnchorCandidate(frame)
    if not IsNameplateAnchorFrame(frame) then return nil end
    local getter = SafeIndex(frame, "GetAnchor")
    if type(getter) == "function" then
        local ok, anchor = pcall(getter, frame)
        if ok and IsNameplateAnchorFrame(anchor) then
            return anchor
        end
    end
    return frame
end

-- MDR-style: get the canonical anchor frame for a nameplate.
local function GetNameplateAnchorFrame(nameplate)
    if not nameplate or IsForbidden(nameplate) then return nil end

    local tp = SafeIndex(nameplate, "TPFrame")
    local anchor = ResolveNameplateAnchorCandidate(tp)
    if anchor then return anchor end

    local uf = SafeIndex(nameplate, "UnitFrame") or SafeIndex(nameplate, "unitFrame")

    anchor = ResolveNameplateAnchorCandidate(SafeIndex(nameplate, "AnchorFrame"))
    if anchor then return anchor end

    anchor = ResolveNameplateAnchorCandidate(SafeIndex(uf, "AnchorFrame"))
    if anchor then return anchor end

    anchor = ResolveNameplateAnchorCandidate(uf)
    if anchor then return anchor end

    anchor = ResolveNameplateAnchorCandidate(nameplate)
    if anchor then return anchor end

    return uf or nameplate
end

local function BuildCompositeKey(unit)
    if type(unit) ~= "string" then return nil end
    local honor = SafeUnitHonorLevel(unit)
    local classToken = SafeUnitClassToken(unit)
    local raceName = SafeUnitRaceName(unit)
    if type(classToken) ~= "string" or type(raceName) ~= "string" then return nil end
    if type(honor) ~= "number" then honor = 0 end
    local ok, key = pcall(string.format, "%d:%s:%s", honor, classToken, raceName)
    if not ok or type(key) ~= "string" then return nil end
    return key
end

local function IsEnemyPlayerPlateToken(tok)
    if type(tok) ~= "string" or not SafeUnitExists(tok) then return false end
    local isEnemyPlayer = SafeUnitIsEnemy("player", tok)
    local isPlayer = SafeUnitIsPlayer(tok)
    return ((isEnemyPlayer == true and isPlayer == true) or (isEnemyPlayer == nil and isPlayer == true)) and true or false
end

local function ResolveArenaByCompositeKey(unit, plates)
    if type(unit) ~= "string" or not unit:find("^arena%d$") then return nil end
    if type(plates) ~= "table" then return nil end

    local arenaKey = BuildCompositeKey(unit)
    if not arenaKey then return nil end

    local foundTok, foundNameplate, foundAnchor = nil, nil, nil
    for _, np in ipairs(plates) do
        if np and (not IsForbidden(np)) then
            local tok = PlateToken(np)
            if IsEnemyPlayerPlateToken(tok) then
                local plateKey = BuildCompositeKey(tok)
                if plateKey and plateKey == arenaKey then
                    local anchor = GetNameplateAnchorFrame(np)
                    if foundTok and foundTok ~= tok then
                        return nil
                    end
                    foundTok, foundNameplate, foundAnchor = tok, np, anchor
                end
            end
        end
    end

    return foundTok, foundNameplate, foundAnchor
end

local function ClearArenaCache(arenaUnit)
    local c = npAnchorCache[arenaUnit]
    if c and c.token then
        npTokenToArena[c.token] = nil
    end
    npAnchorCache[arenaUnit] = nil
end

local function CacheValid(arenaUnit, plates)
    local c = npAnchorCache[arenaUnit]
    if not c or type(c.token) ~= "string" or not c.anchor or IsForbidden(c.anchor) then
        return nil, nil
    end

    if not SafeUnitExists(c.token) then
        ClearArenaCache(arenaUnit)
        return nil, nil
    end

    local arenaKey = BuildCompositeKey(arenaUnit)
    local tokenKey = BuildCompositeKey(c.token)
    if not arenaKey or not tokenKey or arenaKey ~= tokenKey then
        ClearArenaCache(arenaUnit)
        return nil, nil
    end

    for _, np in ipairs(plates) do
        if np and (not IsForbidden(np)) then
            local tok = PlateToken(np)
            if tok == c.token then
                local a = GetNameplateAnchorFrame(np)
                c.nameplate = np
                c.anchor = a
                return np, a
            end
        end
    end

    ClearArenaCache(arenaUnit)
    return nil, nil
end

local function CacheBind(arenaUnit, token, nameplate, anchor)
    if not arenaUnit or not token or not anchor then return end
    local old = npAnchorCache[arenaUnit]
    if old and old.token and old.token ~= token then
        npTokenToArena[old.token] = nil
    end
    npAnchorCache[arenaUnit] = { token = token, nameplate = nameplate, anchor = anchor }
    npTokenToArena[token] = arenaUnit
end

local function GetDirectNameplate(unit, plates)
    if type(C_NamePlate) == "table" and type(C_NamePlate.GetNamePlateForUnit) == "function" then
        local ok, np = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok and np and (not IsForbidden(np)) then
            return np
        end
    end

    if type(unit) == "string" and unit:match("^nameplate%d+$") and type(plates) == "table" then
        for _, np in ipairs(plates) do
            if np and (not IsForbidden(np)) and PlateToken(np) == unit then
                return np
            end
        end
    end

    return nil
end

-- MDR-style: get both nameplate root and anchor frame for a unit.
local function GetNameplateRootAndAnchorForUnit(unit)
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or not plates then return nil, nil end

    if type(unit) == "string" and unit:find("^arena%d$") then
        local cachedNp, cachedAnchor = CacheValid(unit, plates)
        if cachedAnchor then return cachedNp, cachedAnchor end

        local tok, nameplate, anchor = ResolveArenaByCompositeKey(unit, plates)
        if tok and anchor then
            CacheBind(unit, tok, nameplate, anchor)
            return nameplate, anchor
        end

        ClearArenaCache(unit)
        return nil, nil
    end

    local nameplate = GetDirectNameplate(unit, plates)
    if nameplate then
        return nameplate, GetNameplateAnchorFrame(nameplate)
    end
    return nil, nil
end

function sArenaMixin:GetNameplateAnchorForArena(unit)
    local _, anchor = GetNameplateRootAndAnchorForUnit(unit)
    return anchor
end

function sArenaMixin:ClearNameplateAnchorCache(token)
    if token then
        local au = npTokenToArena[token]
        if au then ClearArenaCache(au) end
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
        cd:SetHideCountdownNumbers(false)
        f.Cooldown = cd

        -- DIY: when the nameplate mirror cooldown (drResetTime, e.g. 16.1s) finishes,
        -- clear our own icon/cooldown and reflow positions. Health bar uses a longer
        -- duration (drResetTime + leeway) to mask Blizzard's expiry bug, so without
        -- this self-clean we'd see the nameplate icon "stuck" for a few seconds after
        -- the swipe completes.
        local arenaFrame = self
        cd:HookScript("OnCooldownDone", function()
            if f.Icon then f.Icon:SetTexture(nil) end
            f.Cooldown:Clear()
            f:Hide()
            if arenaFrame.UpdateNameplateDRPositions then
                arenaFrame:UpdateNameplateDRPositions()
            end
        end)

        local cdText = nil
        if cd.GetRegions then
            for _, region in next, { cd:GetRegions() } do
                if region:GetObjectType() == "FontString" then
                    cdText = region
                    break
                end
            end
        end
        if not cdText and cd.GetCountdownFontString then
            cdText = cd:GetCountdownFontString()
        end
        f.CDText = cdText

        -- Border layout (MDR-style): TWO parallel border sets stacked on top of
        -- each other. The green set is visible by default, the red set is fully
        -- transparent. The ImmunityIndicator hook drives both alphas via
        -- Region:SetAlphaFromBoolean so we never touch the (potentially secret)
        -- 'shown' boolean directly. Inverse alpha = inverse visibility.
        local borderFrame = CreateFrame("Frame", nil, f)
        borderFrame:SetPoint("TOPLEFT", -1, 1)
        borderFrame:SetPoint("BOTTOMRIGHT", 1, -1)
        borderFrame:SetFrameLevel(f:GetFrameLevel() + 2)

        local function makeBorderTextures(parent, r, g, b, initialAlpha)
            local top = parent:CreateTexture(nil, "OVERLAY")
            top:SetHeight(1); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
            top:SetColorTexture(r, g, b, 1); top:SetAlpha(initialAlpha)
            local bot = parent:CreateTexture(nil, "OVERLAY")
            bot:SetHeight(1); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
            bot:SetColorTexture(r, g, b, 1); bot:SetAlpha(initialAlpha)
            local left = parent:CreateTexture(nil, "OVERLAY")
            left:SetWidth(1); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
            left:SetColorTexture(r, g, b, 1); left:SetAlpha(initialAlpha)
            local right = parent:CreateTexture(nil, "OVERLAY")
            right:SetWidth(1); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
            right:SetColorTexture(r, g, b, 1); right:SetAlpha(initialAlpha)
            return { top, bot, left, right }
        end

        f.BorderTextures = makeBorderTextures(borderFrame, 0, 1, 0, 1) -- green, visible
        f.RedBorderTextures = makeBorderTextures(borderFrame, 1, 0, 0, 0) -- red, hidden

        -- Glow wrapped in a Frame so we can drive visibility via the parent
        -- frame's alpha (SetAlphaFromBoolean) without fighting the alpha
        -- animation that runs on the texture itself.
        local glowFrame = CreateFrame("Frame", nil, f)
        glowFrame:SetPoint("TOPLEFT", -3, 3)
        glowFrame:SetPoint("BOTTOMRIGHT", 3, -3)
        glowFrame:SetAlpha(0)
        f.GlowFrame = glowFrame

        f.GlowTexture = glowFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        f.GlowTexture:SetAllPoints()
        f.GlowTexture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        f.GlowTexture:SetBlendMode("ADD")
        f.GlowTexture:SetAlpha(0.8)

        self.drFramesNP[s] = f
    end
end

-- Drive the green/red border visibility from the (possibly secret) 'shown'
-- boolean coming straight from the ImmunityIndicator hook. SetAlphaFromBoolean
-- is the only safe way to consume a secret boolean: it never tests the value
-- in Lua, so it never taints us.
function sArenaFrameMixin:SetNameplateDRBorderImmunity(slot, shown)
    local f = self.drFramesNP and self.drFramesNP[slot]
    if not f then return end
    if f.BorderTextures then
        for _, tex in ipairs(f.BorderTextures) do
            tex:SetAlphaFromBoolean(shown, 0, 1)
        end
    end
    if f.RedBorderTextures then
        for _, tex in ipairs(f.RedBorderTextures) do
            tex:SetAlphaFromBoolean(shown, 1, 0)
        end
    end
end

-- Glow visibility is gated by two separate signals:
--   * glowEnabled : a regular Lua bool from user db (master switch)
--   * shown       : a possibly-secret boolean from the ImmunityIndicator hook
-- We branch only on the regular bool, then route the secret bool through
-- SetAlphaFromBoolean on the glow's parent frame. The looping alpha animation
-- runs on the texture itself, which is independent from the parent frame's
-- alpha, so the two never fight.
function sArenaFrameMixin:SetNameplateDRGlow(slot, glowEnabled, shown, r, g, b)
    if not self.drFramesNP then return end
    local f = self.drFramesNP[slot]
    if not f or not f.GlowTexture or not f.GlowFrame then return end

    if glowEnabled then
        f.GlowTexture:SetVertexColor(r or 1, g or 0, b or 0)
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
        if not f.glowAnim:IsPlaying() then f.glowAnim:Play() end
        f.GlowFrame:SetAlphaFromBoolean(shown, 1, 0)
    else
        if f.glowAnim and f.glowAnim:IsPlaying() then f.glowAnim:Stop() end
        f.GlowFrame:SetAlpha(0)
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

    if not layoutdb.drNameplateEnabled then
        for _, f in ipairs(self.drFramesNP) do f:Hide() end
        return
    end

    -- 检查区域开关：如果当前在竞技场且用户关闭了竞技场区域，则隐藏姓名版递减
    local _, instanceType = IsInInstance()
    if instanceType == "arena" then
        local globaldb = self.parent.db
        if globaldb and globaldb.profile and globaldb.profile.nameplateDRZones then
            if globaldb.profile.nameplateDRZones.enableInArena == false then
                for _, f in ipairs(self.drFramesNP) do f:Hide() end
                return
            end
        end
    end

    local arenaUnit = "arena" .. self:GetID()
    local anchor = self.parent:GetNameplateAnchorForArena(arenaUnit)

    if not anchor or IsForbidden(anchor) then
        for _, f in ipairs(self.drFramesNP) do f:Hide() end
        return
    end

    -- MDR-compatible scale sync:
    -- 12.0.5+ clients changed nameplate scaling behavior; the old UIParent +
    -- SetScale(us/ps) hack is prone to "jumping" (selected nameplate scale) and
    -- inconsistent size/alpha between arena and world.
    --
    -- Mirror MDR: parent each NP DR icon to the nameplate anchor and rely on
    -- inheriting parent scale (SetIgnoreParentScale(false)) while keeping our
    -- own alpha (SetIgnoreParentAlpha(true)). We then keep our own scale at 1.

    local fontSize = db.fontSize or 12
    local hideText = db.hideText
    local borderSz = db.borderSize or 1
    local drAlpha = db.alpha or 1.0

    local numActive = 0
    local prevFrame
    for _, f in ipairs(self.drFramesNP) do
        -- Parent to anchor so scale tracks nameplate (MDR strategy)
        if f.GetParent and f.SetParent and f:GetParent() ~= anchor then
            pcall(function() f:SetParent(anchor) end)
        end
        pcall(function() f:SetIgnoreParentScale(false) end)
        pcall(function() f:SetIgnoreParentAlpha(true) end)
        f:SetSize(size, size)
        f:SetScale(1)
        f:SetAlpha(drAlpha)
        f.Cooldown:SetHideCountdownNumbers(hideText and true or false)
        -- DIY: only adjust border thickness here. Border colors are baked in
        -- by SetColorTexture at frame creation time (green for BorderTextures,
        -- red for RedBorderTextures). Visibility is driven via alpha from the
        -- ImmunityIndicator hook (SetNameplateDRBorderImmunity), so we must NOT
        -- call SetColorTexture / GetVertexColor here -- that would clobber the
        -- active color to white because GetVertexColor returns the vertex color
        -- (default (1,1,1)), which is independent from the color baked in by
        -- SetColorTexture.
        local function resizeBorders(tbl)
            if not tbl then return end
            for _, tex in ipairs(tbl) do
                tex:SetHeight(borderSz)
                tex:SetWidth(borderSz)
            end
        end
        resizeBorders(f.BorderTextures)
        resizeBorders(f.RedBorderTextures)
        if f.CDText and not hideText then
            local fontFile = f.CDText.fontFile or select(1, f.CDText:GetFont())
            local flags = f.CDText.fontFlags or select(3, f.CDText:GetFont())
            if fontFile then
                pcall(function() f.CDText:SetFont(fontFile, fontSize, flags or "OUTLINE") end)
            end
        end

        -- Re-show frames that were hidden by anchor loss but still have an active DR
        if not f:IsShown() then
            local hasTex = false
            pcall(function() hasTex = f.Icon:GetTexture() ~= nil end)
            if hasTex then f:Show() end
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
    -- MDR-compatible: try target/mouseover through proper anchor resolution,
    -- then fall back to scanning visible nameplates.
    local np, a = GetNameplateRootAndAnchorForUnit("target")
    if a then return a end
    np, a = GetNameplateRootAndAnchorForUnit("mouseover")
    if a then return a end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and plates then
        for _, p in ipairs(plates) do
            local anchor = GetNameplateAnchorFrame(p)
            if anchor and (not IsForbidden(anchor)) then
                local shownOk, shown = pcall(function() return anchor:IsShown() end)
                if shownOk and shown then return anchor end
            end
        end
    end
    return nil
end

-- Test mode uses a dedicated set of frames (_testNPDRFrames) instead of arena1.drFramesNP,
-- so it never collides with the real-DR data path and can ignore enabled / zone / instanceType
-- guards entirely. Purpose: pure visual preview for sliders (size, position, font, border, alpha).

local NP_DR_TEST_TEXTURES = { 136071, 132298, 136100, 136183 }
local NP_DR_TEST_COLORS   = { {1,0,0}, {0,1,0}, {0,1,0}, {0,1,0} }
local NP_DR_TEST_COUNT    = 4

local function CreateTestNPDRFrame(idx)
    local name = "sArenaTestNPDR" .. idx
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(22, 22)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(210)
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
    cd:SetReverse(true)
    cd:SetSwipeColor(0, 0, 0, 0.6)
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
        t:SetColorTexture(0, 1, 0, 1)
        return t
    end
    local bTop = makeLine(); bTop:SetHeight(1); bTop:SetPoint("TOPLEFT"); bTop:SetPoint("TOPRIGHT")
    local bBot = makeLine(); bBot:SetHeight(1); bBot:SetPoint("BOTTOMLEFT"); bBot:SetPoint("BOTTOMRIGHT")
    local bLeft = makeLine(); bLeft:SetWidth(1); bLeft:SetPoint("TOPLEFT"); bLeft:SetPoint("BOTTOMLEFT")
    local bRight = makeLine(); bRight:SetWidth(1); bRight:SetPoint("TOPRIGHT"); bRight:SetPoint("BOTTOMRIGHT")
    f.BorderTextures = { bTop, bBot, bLeft, bRight }

    return f
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
    local hideText = db.hideText
    local fontSize = db.fontSize or 12
    local borderSz = db.borderSize or 1
    local drAlpha = db.alpha or 1.0

    local us = (anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or 1
    local ps = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local sc = us / ps
    if sc < 0.1 then sc = 0.1 elseif sc > 10 then sc = 10 end

    self._testNPDRFrames = self._testNPDRFrames or {}
    self._testNPDRCDs = self._testNPDRCDs or {}

    local prevFrame
    for n = 1, NP_DR_TEST_COUNT do
        local f = self._testNPDRFrames[n]
        if not f then
            f = CreateTestNPDRFrame(n)
            self._testNPDRFrames[n] = f
        end

        f:SetSize(size, size)
        f:SetScale(sc)
        f:SetAlpha(drAlpha)
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

        f.Icon:SetTexture(NP_DR_TEST_TEXTURES[n])
        f.Icon:SetDesaturated(false)
        f.Icon:SetVertexColor(1, 1, 1, 1)

        local cd = self._testNPDRCDs[n]
        local nowT = GetTime()
        if not cd or (cd.start + cd.duration) <= nowT then
            cd = { start = nowT, duration = math.random(12, 30) }
            self._testNPDRCDs[n] = cd
        end
        f.Cooldown:Clear()
        f.Cooldown:SetCooldown(cd.start, cd.duration)
        f.Cooldown:SetHideCountdownNumbers(hideText and true or false)

        if f.CDText and not hideText then
            local fontFile = f.CDText.fontFile or select(1, f.CDText:GetFont())
            local flags = f.CDText.fontFlags or select(3, f.CDText:GetFont())
            if fontFile then
                pcall(function() f.CDText:SetFont(fontFile, fontSize, flags or "OUTLINE") end)
            end
        end

        if f.BorderTextures then
            local color = NP_DR_TEST_COLORS[n]
            for _, tex in ipairs(f.BorderTextures) do
                tex:SetColorTexture(color[1], color[2], color[3], 1)
                tex:SetHeight(borderSz)
                tex:SetWidth(borderSz)
            end
        end

        f:Show()
        prevFrame = f
    end
end

function sArenaMixin:HideTestNameplateDR()
    if self._testNPDRFrames then
        for _, f in ipairs(self._testNPDRFrames) do
            if f then
                if f.Icon then f.Icon:SetTexture(nil) end
                if f.Cooldown then f.Cooldown:Clear() end
                f:ClearAllPoints()
                f:Hide()
            end
        end
    end
    self._testNPDRCDs = nil
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

-- =============================================
-- World / BG Nameplate DR (ported from MidnightDR Basic)
-- Tracks player's own casts via UNIT_SPELLCAST_SUCCEEDED
-- =============================================

local SPELLS = {
    stun = {
        [408]=5,[853]=5,[1833]=4,[19577]=3,[24394]=3,[5211]=4,[89766]=3,[91797]=3,
        [91800]=3,[107570]=3,[108194]=3,[109248]=3,[117526]=3,[118345]=3,[118905]=3,
        [119381]=5,[1234195]=3,[132168]=3,[132169]=3,[145047]=3,[163505]=4,[171017]=3,[171018]=3,
        [179057]=3,[199085]=3,[200166]=3,[200200]=3,[202244]=3,[202346]=3,[203123]=3,
        [20549]=3,[205630]=3,[208618]=3,[210141]=3,[211881]=3,[221562]=3,[255723]=3,
        [255941]=3,[287254]=3,[287712]=3,[30283]=3,[305485]=3,[325321]=3,[332423]=3,
        [357021]=3,[372245]=3,[377048]=3,[385954]=3,[389831]=3,[408544]=3,[458605]=3,
        [46968]=3,[64044]=3,[1822]=4,[22570]=5,
    },
    incap = {
        [99]=3,[118]=6,[710]=6,[1776]=3,[2637]=6,[3355]=6,[6770]=6,[6789]=3,[9484]=6,
        [20066]=6,[200196]=3,[28271]=6,[28272]=6,[51514]=6,[61025]=6,[61305]=6,
        [61721]=6,[61780]=6,[82691]=6,[107079]=6,[115078]=3,[126819]=6,[161353]=6,
        [161354]=6,[161355]=6,[161372]=6,[196942]=6,[197214]=6,[203337]=6,[210873]=6,
        [211004]=6,[211010]=6,[211015]=6,[213691]=6,[217832]=3,[221527]=6,[269352]=6,
        [277778]=6,[277784]=6,[277787]=6,[277792]=6,[309328]=6,[321395]=6,[357768]=6,
        [378441]=6,[383121]=6,[391622]=6,[460396]=6,[461489]=6,
    },
    fear = {
        [605]=6,[1513]=6,[2094]=5,[31661]=4,[33786]=5,[353084]=6,[5246]=5,[5484]=6,
        [5782]=6,[6358]=6,[8122]=6,[10326]=6,[105421]=6,[115750]=4,[118699]=6,
        [130616]=6,[198909]=6,[202274]=6,[205364]=6,[207167]=4,[207685]=6,[261589]=6,
        [316593]=6,[316595]=6,[324263]=6,[331866]=6,[360806]=6,
    },
    root = {
        [122]=6,[339]=6,[33395]=6,[39965]=6,[55536]=6,[64695]=6,[75148]=6,[102359]=6,
        [114404]=6,[116706]=6,[162480]=6,[170855]=6,[190927]=6,[199042]=6,[199786]=6,
        [201158]=6,[204085]=6,[212638]=6,[233395]=6,[235963]=6,[268966]=6,[285515]=6,
        [324382]=6,[342375]=6,[356356]=6,[356738]=6,[355689]=6,[378760]=6,[386770]=6,
        [393456]=6,[454787]=6,[16979]=6,
    },
    disarm = {
        [207777]=5,[209749]=5,[233759]=5,[236077]=5,[407031]=5,[407032]=5,
    },
    silence = {
        [703]=3,[1330]=3,[15487]=4,[47476]=4,[202914]=4,[202933]=4,[204490]=6,
        [217824]=4,[354831]=3,[355596]=3,[356727]=3,[374776]=3,[392058]=3,[392060]=3,
        [392061]=3,[410065]=3,[196364]=4,
    },
}

local CATEGORY_ORDER = { "stun", "incap", "fear", "root", "disarm", "silence" }

local spellToInfo = {}
for _, cat in ipairs(CATEGORY_ORDER) do
    if SPELLS[cat] then
        for spellID, dur in pairs(SPELLS[cat]) do
            spellToInfo[spellID] = { cat = cat, dur = dur }
        end
    end
end

local CATEGORY_FALLBACK_ICON = {
    stun = 132298, incap = 136071, fear = 136183,
    root = 136100, disarm = 132343, silence = 458736,
}

local function WorldDR_IsCategoryEnabled(cat)
    local f = GetSArenaFrame()
    local db = f and f.db
    if not db or not db.profile then return true end
    local cats = db.profile.nameplateDRCategories
    if not cats then return true end
    local v = cats[cat]
    if v == nil then return true end
    return v ~= false
end

local function WorldDR_GetMaxIcons()
    local f = GetSArenaFrame()
    local db = f and f.db
    if not db or not db.profile then return 5 end
    local m = db.profile.nameplateDRMaxIcons
    if type(m) ~= "number" then return 5 end
    if m < 1 then return 1 elseif m > 6 then return 6 end
    return m
end

local worldDRState = {
    unitToGuid = {},
    guidToUnit = {},
    unitToKey = {},
    keyToUnit = {},
    active = {},
    activeKey = {},
    widgets = {},
    ticker = nil,
    running = false,
}

local function WorldDR_IsArena()
    local _, it = IsInInstance()
    return it == "arena"
end

local function WorldDR_IsBattleground()
    local _, it = IsInInstance()
    return it == "pvp"
end

local function WorldDR_GetInstanceType()
    local _, it = IsInInstance()
    return it
end

local function WorldDR_IsEnabledForZone(db)
    if not db or not db.profile then return false end
    local zones = db.profile.nameplateDRZones
    if not zones then return false end
    local it = WorldDR_GetInstanceType()
    if it == "arena" then
        return zones.enableInArena ~= false
    elseif it == "pvp" then
        return zones.enableInBattleground == true
    elseif it == "none" then
        return zones.enableInWorld == true
    elseif it == "party" or it == "raid" or it == "scenario" then
        return zones.enableInDungeon == true
    end
    return false
end

local function WorldDR_BuildCompositeKey(unit)
    if not UnitExists(unit) then return nil end
    local ok1, h = pcall(UnitHonorLevel, unit)
    local ok2, _, classToken = pcall(UnitClass, unit)
    local ok3, raceName = pcall(UnitRace, unit)
    if not ok2 or not classToken then return nil end
    local side = "E"
    local ok4, fr = pcall(UnitIsFriend, "player", unit)
    if ok4 and fr then side = "F" end
    return tostring(h or 0) .. ":" .. tostring(classToken) .. ":" .. tostring(raceName or "?") .. ":" .. side
end

local function WorldDR_GetSpellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex then return tex end
    end
    return nil
end

local function WorldDR_ScanNameplates()
    if WorldDR_IsArena() then return end
    local inBG = WorldDR_IsBattleground()
    if inBG then
        wipe(worldDRState.unitToKey)
        wipe(worldDRState.keyToUnit)
    else
        wipe(worldDRState.unitToGuid)
        wipe(worldDRState.guidToUnit)
    end
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    local plates = C_NamePlate.GetNamePlates()
    for i = 1, #plates do
        local plate = plates[i]
        if plate and not IsForbidden(plate) then
            local unit = SafeIndex(plate, "namePlateUnitToken") or SafeIndex(plate, "unitToken")
            if type(unit) == "string" then
                if inBG then
                    local key = WorldDR_BuildCompositeKey(unit)
                    if key then
                        worldDRState.unitToKey[unit] = key
                        worldDRState.keyToUnit[key] = unit
                    end
                else
                    local guid = SafeUnitGUID(unit)
                    if guid then
                        worldDRState.unitToGuid[unit] = guid
                        worldDRState.guidToUnit[guid] = unit
                    end
                end
            end
        end
    end
end

local function WorldDR_MakeThinPixelBorder(parent, r, g, b, a)
    a = (a == nil) and 1 or a
    local fr = CreateFrame("Frame", nil, parent)
    fr:SetAllPoints(parent)
    local function line()
        local t = fr:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(r, g, b, a)
        return t
    end
    fr.top    = line(); fr.top:SetPoint("TOPLEFT", fr, 0, 0); fr.top:SetPoint("TOPRIGHT", fr, 0, 0); fr.top:SetHeight(1)
    fr.bottom = line(); fr.bottom:SetPoint("BOTTOMLEFT", fr, 0, 0); fr.bottom:SetPoint("BOTTOMRIGHT", fr, 0, 0); fr.bottom:SetHeight(1)
    fr.left   = line(); fr.left:SetPoint("TOPLEFT", fr, 0, 0); fr.left:SetPoint("BOTTOMLEFT", fr, 0, 0); fr.left:SetWidth(1)
    fr.right  = line(); fr.right:SetPoint("TOPRIGHT", fr, 0, 0); fr.right:SetPoint("BOTTOMRIGHT", fr, 0, 0); fr.right:SetWidth(1)
    return fr
end

local function WorldDR_SetBorderThickness(b, px)
    if not b then return end
    px = tonumber(px) or 1
    if px < 1 then px = 1 end
    if b.top    and b.top.SetHeight    then b.top:SetHeight(px) end
    if b.bottom and b.bottom.SetHeight then b.bottom:SetHeight(px) end
    if b.left   and b.left.SetWidth    then b.left:SetWidth(px) end
    if b.right  and b.right.SetWidth   then b.right:SetWidth(px) end
end

local function WorldDR_FormatDRRemainingText(rem)
    if type(rem) ~= "number" or rem <= 0 then return nil end
    if rem < 3 then
        if rem < 0.1 then rem = 0.1 end
        rem = math.floor(rem * 10) / 10
        return string.format("%.1f", rem)
    end
    return tostring(math.floor(rem))
end

local function WorldDR_IsEnabled()
    local f = GetSArenaFrame()
    local ldb = f and f.layoutdb
    return ldb and ldb.drNameplateEnabled
end

local function WorldDR_EnsureWidget(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit) or nil
    if not plate then return nil end
    if IsForbidden(plate) then return nil end

    local uf = SafeIndex(plate, "UnitFrame") or SafeIndex(plate, "unitFrame") or plate
    if (not uf) or IsForbidden(uf) then return nil end

    local w = worldDRState.widgets[unit]
    if w and IsForbidden(w) then
        worldDRState.widgets[unit] = nil
        w = nil
    end

    if not w then
        w = CreateFrame("Frame", nil, UIParent)
        w:SetFrameStrata("HIGH")
        w:SetFrameLevel(1000)
        w:SetSize(1, 1)
        w:Hide()

        w.unit = unit
        w.plate = plate
        w.uf = uf

        w.icons = {}
        for i = 1, 5 do
            local f = CreateFrame("Frame", nil, w)
            f:SetFrameStrata("HIGH")
            f:SetFrameLevel(w:GetFrameLevel() + 1)

            f.texture = f:CreateTexture(nil, "ARTWORK")
            f.texture:SetAllPoints()

            f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
            f.cooldown:SetAllPoints()
            f.cooldown:SetDrawEdge(false)
            f.cooldown:SetDrawSwipe(true)
            f.cooldown:SetReverse(true)
            f.cooldown:SetSwipeColor(0, 0, 0, 0.8)
            f.cooldown:SetHideCountdownNumbers(true)
            f.cooldown:SetFrameLevel(f:GetFrameLevel() + 1)

            f.textHolder = CreateFrame("Frame", nil, f)
            f.textHolder:SetAllPoints()
            f.textHolder:SetFrameStrata(f:GetFrameStrata())
            f.textHolder:SetFrameLevel(f:GetFrameLevel() + 10)

            f.text = f.textHolder:CreateFontString(nil, "OVERLAY")
            f.text:SetDrawLayer("OVERLAY", 7)
            f.text:SetPoint("CENTER", f.textHolder, "CENTER", 0, 0)
            f.text:SetJustifyH("CENTER")
            f.text:SetJustifyV("MIDDLE")

            f.borderFrame = CreateFrame("Frame", nil, f)
            f.borderFrame:SetAllPoints()
            f.borderFrame:SetFrameStrata(f:GetFrameStrata())
            f.borderFrame:SetFrameLevel(f:GetFrameLevel() + 5)
            f.greenBorder = WorldDR_MakeThinPixelBorder(f.borderFrame, 0, 1, 0, 1)
            f.redBorder   = WorldDR_MakeThinPixelBorder(f.borderFrame, 1, 0, 0, 1)
            f.greenBorder:Hide()
            f.redBorder:Hide()

            f:Hide()
            w.icons[i] = f
        end

        worldDRState.widgets[unit] = w
    else
        w.plate = plate
        w.uf = uf
    end

    return w
end

local function WorldDR_ApplyLayout(w)
    if not w then return end
    local f = GetSArenaFrame()
    local ldb = f and f.layoutdb
    local npdb = ldb and ldb.drNameplate

    local size = tonumber(npdb and npdb.size) or 26
    local spacing = tonumber(npdb and npdb.spacing) or 2
    local px = tonumber(npdb and npdb.posX) or 0
    local py = tonumber(npdb and npdb.posY) or 0
    local growNum = (npdb and npdb.growthDirection) or 3
    local fontSize = tonumber(npdb and npdb.fontSize) or 14

    local GROW_MAP = { [1] = "DOWN", [2] = "UP", [3] = "RIGHT", [4] = "LEFT" }
    local grow = GROW_MAP[growNum] or "RIGHT"

    w:ClearAllPoints()
    if w.uf then
        w:SetPoint("CENTER", w.uf, "CENTER", px, py)
    elseif w.plate then
        w:SetPoint("CENTER", w.plate, "CENTER", px, py)
    else
        w:SetPoint("CENTER", UIParent, "CENTER", px, py)
    end

    -- MDR-compatible scale sync:
    -- parent the widget to the nameplate UnitFrame (or plate) and inherit its
    -- scale naturally instead of copying us/ps.
    local parentFrame = w.uf or w.plate or UIParent
    if w.GetParent and w.SetParent and parentFrame and w:GetParent() ~= parentFrame then
        pcall(function() w:SetParent(parentFrame) end)
    end
    pcall(function() w:SetIgnoreParentScale(false) end)
    pcall(function() w:SetIgnoreParentAlpha(true) end)
    pcall(function() w:SetScale(1) end)

    local alpha = tonumber(npdb and npdb.alpha) or 1
    w:SetAlpha(alpha)

    local fontPath = "Fonts\\FRIZQT__.TTF"
    for i, f in ipairs(w.icons) do
        f:SetSize(size, size)
        f.text:SetFont(fontPath, fontSize, "OUTLINE")
        f.text:SetTextColor(1, 1, 1, 1)

        f:ClearAllPoints()
        local dx, dy = 0, 0
        if grow == "LEFT" then dx = -(i-1) * (size + spacing)
        elseif grow == "UP" then dy = (i-1) * (size + spacing)
        elseif grow == "DOWN" then dy = -(i-1) * (size + spacing)
        else dx = (i-1) * (size + spacing)
        end
        f:SetPoint("CENTER", w, "CENTER", dx, dy)
    end
end

local function WorldDR_HideWidget(unit)
    local w = worldDRState.widgets[unit]
    if w then w:Hide() end
end

local function WorldDR_ClearWidgetIcons(w)
    if not w then return end
    for _, f in ipairs(w.icons) do
        if f.greenBorder then f.greenBorder:Hide() end
        if f.redBorder   then f.redBorder:Hide() end
        f:Hide()
    end
end

local function WorldDR_RenderOnUnit(unit, states)
    local w = WorldDR_EnsureWidget(unit)
    if not w then return end

    WorldDR_ApplyLayout(w)
    WorldDR_ClearWidgetIcons(w)

    local maxIcons = WorldDR_GetMaxIcons()
    local sf = GetSArenaFrame()
    local npdb = sf and sf.layoutdb and sf.layoutdb.drNameplate
    local borderSize = tonumber(npdb and npdb.borderSize) or 1

    local now = GetTime()
    local shown = 0
    for _, cat in ipairs(CATEGORY_ORDER) do
        if shown >= maxIcons then break end
        if WorldDR_IsCategoryEnabled(cat) then
            local st = states and states[cat]
            if st and st.finish and st.finish > now then
                shown = shown + 1
                local f = w.icons[shown]
                if f then
                    local tex = st.tex or WorldDR_GetSpellTexture(st.spellID) or CATEGORY_FALLBACK_ICON[cat]
                    if tex then f.texture:SetTexture(tex) end

                    local dur = st.finish - st.start
                    if dur < 0 then dur = 0 end
                    f.cooldown:SetCooldown(st.start, dur)

                    local rem = st.finish - now
                    if rem < 0 then rem = 0 end
                    local txt = WorldDR_FormatDRRemainingText(rem)
                    if txt then
                        f.text:SetText(txt)
                    else
                        f.text:SetText("")
                    end

                    local rc = tonumber(st.resetCount) or 0
                    if f.greenBorder then
                        WorldDR_SetBorderThickness(f.greenBorder, borderSize)
                        if rc == 0 then f.greenBorder:Show() else f.greenBorder:Hide() end
                    end
                    if f.redBorder then
                        WorldDR_SetBorderThickness(f.redBorder, borderSize)
                        if rc >= 1 then f.redBorder:Show() else f.redBorder:Hide() end
                    end

                    f:Show()
                end
            end
        end
    end

    if shown > 0 then w:Show() else w:Hide() end
end

local function WorldDR_AddTimer(spellID, id, isKey)
    local info = spellToInfo[spellID]
    if not info then return end
    if not WorldDR_IsCategoryEnabled(info.cat) then return end
    local tbl = isKey and worldDRState.activeKey or worldDRState.active
    local lookup = isKey and worldDRState.keyToUnit or worldDRState.guidToUnit
    local now = GetTime()
    tbl[id] = tbl[id] or {}
    local st = tbl[id][info.cat]
    local d, resetCount
    if st and st.finish and st.finish > now then
        if (st.resetCount or 0) >= 1 then return end
        resetCount = 1
        d = ((st.d and st.d > 0) and st.d or info.dur) / 2
    else
        resetCount = 0
        d = info.dur
    end
    if d < 0.5 then d = 0.5 end
    local total = d + 0.4 + 16
    local tex = WorldDR_GetSpellTexture(spellID) or CATEGORY_FALLBACK_ICON[info.cat]
    tbl[id][info.cat] = {
        start = now, finish = now + total, d = d,
        resetCount = resetCount, spellID = spellID, tex = tex,
    }
    local unit = lookup[id]
    if not unit then WorldDR_ScanNameplates(); unit = lookup[id] end
    if unit then WorldDR_RenderOnUnit(unit, tbl[id]) end
end

local function WorldDR_CleanExpired(tbl)
    local now = GetTime()
    for id, cats in pairs(tbl) do
        local any = false
        for cat, st in pairs(cats) do
            if not st.finish or st.finish <= now then cats[cat] = nil else any = true end
        end
        if not any then tbl[id] = nil end
    end
end

local function WorldDR_Tick()
    local sf = GetSArenaFrame()
    if not sf or not sf.db then return end
    if not WorldDR_IsEnabled() then
        for unit in pairs(worldDRState.widgets) do WorldDR_HideWidget(unit) end
        return
    end
    if not WorldDR_IsEnabledForZone(sf.db) then
        for unit in pairs(worldDRState.widgets) do WorldDR_HideWidget(unit) end
        return
    end
    if WorldDR_IsArena() then
        for unit in pairs(worldDRState.widgets) do WorldDR_HideWidget(unit) end
        return
    end

    local inBG = WorldDR_IsBattleground()
    if inBG then
        if not next(worldDRState.keyToUnit) then WorldDR_ScanNameplates() end
        WorldDR_CleanExpired(worldDRState.activeKey)
        for key, unit in pairs(worldDRState.keyToUnit) do
            local states = worldDRState.activeKey[key]
            if states then WorldDR_RenderOnUnit(unit, states)
            else WorldDR_HideWidget(unit) end
        end
    else
        if not next(worldDRState.guidToUnit) then WorldDR_ScanNameplates() end
        WorldDR_CleanExpired(worldDRState.active)
        for guid, unit in pairs(worldDRState.guidToUnit) do
            local states = worldDRState.active[guid]
            if states then WorldDR_RenderOnUnit(unit, states)
            else WorldDR_HideWidget(unit) end
        end
    end
end

function sArenaMixin:WorldDR_OnSpellcastSucceeded(unit, _, spellID)
    if unit ~= "player" or type(spellID) ~= "number" then return end
    if not self.db or not WorldDR_IsEnabled() or not WorldDR_IsEnabledForZone(self.db) then
        return
    end
    if WorldDR_IsArena() then return end
    if not UnitExists("target") or not UnitCanAttack("player", "target") then return end
    if WorldDR_IsBattleground() then
        local key = WorldDR_BuildCompositeKey("target")
        if key then WorldDR_AddTimer(spellID, key, true) end
    else
        local guid = SafeUnitGUID("target")
        if guid then WorldDR_AddTimer(spellID, guid, false) end
    end
end

function sArenaMixin:WorldDR_OnNamePlateAdded(unit)
    if WorldDR_IsArena() then return end
    if WorldDR_IsBattleground() then
        local key = WorldDR_BuildCompositeKey(unit)
        if key then
            worldDRState.unitToKey[unit] = key
            worldDRState.keyToUnit[key] = unit
        end
    else
        local guid = SafeUnitGUID(unit)
        if guid then
            worldDRState.unitToGuid[unit] = guid
            worldDRState.guidToUnit[guid] = unit
        end
    end
end

function sArenaMixin:WorldDR_OnNamePlateRemoved(unit)
    if WorldDR_IsBattleground() then
        local key = worldDRState.unitToKey[unit]
        worldDRState.unitToKey[unit] = nil
        if key and worldDRState.keyToUnit[key] == unit then worldDRState.keyToUnit[key] = nil end
    else
        local guid = worldDRState.unitToGuid[unit]
        worldDRState.unitToGuid[unit] = nil
        if guid and worldDRState.guidToUnit[guid] == unit then worldDRState.guidToUnit[guid] = nil end
    end
    WorldDR_HideWidget(unit)
end

function sArenaMixin:WorldDR_Start()
    if worldDRState.running then return end
    worldDRState.running = true
    wipe(worldDRState.unitToGuid); wipe(worldDRState.guidToUnit)
    wipe(worldDRState.unitToKey); wipe(worldDRState.keyToUnit)
    WorldDR_ScanNameplates()
    if not worldDRState.ticker then
        worldDRState.ticker = C_Timer.NewTicker(0.016, WorldDR_Tick)
    end
end

function sArenaMixin:WorldDR_Stop()
    if not worldDRState.running then return end
    worldDRState.running = false
    if worldDRState.ticker then worldDRState.ticker:Cancel(); worldDRState.ticker = nil end
    wipe(worldDRState.unitToGuid); wipe(worldDRState.guidToUnit)
    wipe(worldDRState.unitToKey); wipe(worldDRState.keyToUnit)
    for unit in pairs(worldDRState.widgets) do WorldDR_HideWidget(unit) end
end

function sArenaMixin:WorldDR_Evaluate()
    if not self.db then return end
    if not WorldDR_IsEnabled() then
        self:WorldDR_Stop()
        return
    end
    if WorldDR_IsArena() then
        self:WorldDR_Stop()
        return
    end
    if not WorldDR_IsEnabledForZone(self.db) then
        self:WorldDR_Stop()
        return
    end
    self:WorldDR_Start()
end

function sArenaMixin:WorldDR_ShowTest()
    if WorldDR_IsArena() then return end
    local inBG = WorldDR_IsBattleground()

    if inBG then
        if not next(worldDRState.keyToUnit) then WorldDR_ScanNameplates() end
    else
        if not next(worldDRState.guidToUnit) then WorldDR_ScanNameplates() end
    end

    local anchorUnit
    if UnitExists("target") and UnitCanAttack("player", "target") then
        if inBG then
            local key = WorldDR_BuildCompositeKey("target")
            if key and worldDRState.keyToUnit[key] then anchorUnit = worldDRState.keyToUnit[key] end
        else
            local guid = SafeUnitGUID("target")
            if guid and worldDRState.guidToUnit[guid] then anchorUnit = worldDRState.guidToUnit[guid] end
        end
    end
    if not anchorUnit and UnitExists("mouseover") and UnitCanAttack("player", "mouseover") then
        if inBG then
            local key = WorldDR_BuildCompositeKey("mouseover")
            if key and worldDRState.keyToUnit[key] then anchorUnit = worldDRState.keyToUnit[key] end
        else
            local guid = SafeUnitGUID("mouseover")
            if guid and worldDRState.guidToUnit[guid] then anchorUnit = worldDRState.guidToUnit[guid] end
        end
    end
    if not anchorUnit then
        if inBG then
            for unit in pairs(worldDRState.unitToKey) do anchorUnit = unit; break end
        else
            for unit in pairs(worldDRState.unitToGuid) do anchorUnit = unit; break end
        end
    end
    if not anchorUnit then return end

    local now = GetTime()
    local states = {}
    for idx, cat in ipairs(CATEGORY_ORDER) do
        if WorldDR_IsCategoryEnabled(cat) then
            states[cat] = {
                start = now - 1,
                finish = now + (6 - idx) + 2,
                d = 5,
                resetCount = (idx <= 1) and 1 or 0,
                spellID = nil,
                tex = CATEGORY_FALLBACK_ICON[cat],
            }
        end
    end
    WorldDR_RenderOnUnit(anchorUnit, states)
end

function sArenaMixin:WorldDR_HideTest()
    for unit in pairs(worldDRState.widgets) do
        WorldDR_HideWidget(unit)
    end
end
