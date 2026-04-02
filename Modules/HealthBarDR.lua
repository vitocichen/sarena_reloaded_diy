local isMidnight = sArenaMixin.isMidnight
local MAX_DR_SLOTS = 7

function sArenaFrameMixin:CreateHealthBarDRFrames()
    if self.drFramesHB then return end

    self.drFramesHB = {}

    local numSlots = isMidnight and (self.drFrames and #self.drFrames or MAX_DR_SLOTS) or #self.parent.drCategories

    for s = 1, numSlots do
        local name = "sArenaEnemyFrame" .. self:GetID() .. "_HBDR" .. s
        local f = CreateFrame("Frame", name, self)
        f:SetSize(22, 22)
        f:SetFrameStrata("HIGH")
        f:SetFrameLevel(self:GetFrameLevel() + 10)
        f:Hide()

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        f.Icon = icon

        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.7)
        f.Background = bg

        local cd = CreateFrame("Cooldown", name .. "CD", f, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawBling(false)
        cd:SetReverse(true)
        cd:SetSwipeColor(0, 0, 0, 0.6)
        f.Cooldown = cd

        for _, region in next, { cd:GetRegions() } do
            if region:GetObjectType() == "FontString" then
                cd.Text = region
                break
            end
        end

        local border = CreateFrame("Frame", nil, f)
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetFrameLevel(f:GetFrameLevel() + 2)

        local bTop = border:CreateTexture(nil, "OVERLAY")
        bTop:SetHeight(1)
        bTop:SetPoint("TOPLEFT")
        bTop:SetPoint("TOPRIGHT")
        bTop:SetColorTexture(0, 1, 0, 1)
        local bBot = border:CreateTexture(nil, "OVERLAY")
        bBot:SetHeight(1)
        bBot:SetPoint("BOTTOMLEFT")
        bBot:SetPoint("BOTTOMRIGHT")
        bBot:SetColorTexture(0, 1, 0, 1)
        local bLeft = border:CreateTexture(nil, "OVERLAY")
        bLeft:SetWidth(1)
        bLeft:SetPoint("TOPLEFT")
        bLeft:SetPoint("BOTTOMLEFT")
        bLeft:SetColorTexture(0, 1, 0, 1)
        local bRight = border:CreateTexture(nil, "OVERLAY")
        bRight:SetWidth(1)
        bRight:SetPoint("TOPRIGHT")
        bRight:SetPoint("BOTTOMRIGHT")
        bRight:SetColorTexture(0, 1, 0, 1)

        f.Border = border
        f.BorderTextures = { bTop, bBot, bLeft, bRight }

        self.drFramesHB[s] = f
    end
end

function sArenaFrameMixin:SetHealthBarDRBorderColor(slot, r, g, b, a)
    local f = self.drFramesHB and self.drFramesHB[slot]
    if not f or not f.BorderTextures then return end
    for _, tex in ipairs(f.BorderTextures) do
        tex:SetColorTexture(r, g, b, a or 1)
    end
end

function sArenaFrameMixin:SyncHealthBarDR(slot, texture, cdStart, cdDuration, borderR, borderG, borderB)
    if not self.drFramesHB then return end
    local f = self.drFramesHB[slot]
    if not f then return end

    if texture then
        f.Icon:SetTexture(texture)
        if cdStart and cdDuration and cdDuration > 0 then
            f.Cooldown:SetCooldown(cdStart, cdDuration)
        end
        if borderR then
            self:SetHealthBarDRBorderColor(slot, borderR, borderG, borderB)
        end
        f:Show()
    else
        f.Icon:SetTexture(nil)
        f.Cooldown:Clear()
        self:SetHealthBarDRBorderColor(slot, 0, 1, 0, 1)
        f:Hide()
    end

    self:UpdateHealthBarDRPositions()
end

function sArenaFrameMixin:HideAllHealthBarDR()
    if not self.drFramesHB then return end
    for _, f in ipairs(self.drFramesHB) do
        f.Icon:SetTexture(nil)
        f.Cooldown:Clear()
        f:Hide()
    end
end

function sArenaFrameMixin:UpdateHealthBarDRPositions()
    if not self.drFramesHB then return end

    local layoutdb = self.parent.layoutdb
    if not layoutdb or not layoutdb.drHealthBar then return end

    local db = layoutdb.drHealthBar
    local size = db.size or 22
    local spacing = db.spacing or 2
    local grow = db.growthDirection or 3
    local posX = db.posX or 0
    local posY = db.posY or 0
    local fixedPos = layoutdb.dr and layoutdb.dr.fixedPositions

    local anchor = self.HealthBar

    if fixedPos then
        for i, f in ipairs(self.drFramesHB) do
            f:SetSize(size, size)
            f:ClearAllPoints()
            local idx = i - 1
            if grow == 4 then
                f:SetPoint("RIGHT", anchor, "LEFT", posX - idx * (size + spacing), posY)
            elseif grow == 3 then
                f:SetPoint("LEFT", anchor, "RIGHT", posX + idx * (size + spacing), posY)
            elseif grow == 1 then
                f:SetPoint("TOP", anchor, "BOTTOM", posX, posY - idx * (size + spacing))
            elseif grow == 2 then
                f:SetPoint("BOTTOM", anchor, "TOP", posX, posY + idx * (size + spacing))
            end
        end
    else
        local numActive = 0
        local prevFrame
        for _, f in ipairs(self.drFramesHB) do
            f:SetSize(size, size)
            if f:IsShown() then
                f:ClearAllPoints()
                if numActive == 0 then
                    if grow == 4 then
                        f:SetPoint("RIGHT", anchor, "LEFT", posX, posY)
                    elseif grow == 3 then
                        f:SetPoint("LEFT", anchor, "RIGHT", posX, posY)
                    elseif grow == 1 then
                        f:SetPoint("TOP", anchor, "BOTTOM", posX, posY)
                    elseif grow == 2 then
                        f:SetPoint("BOTTOM", anchor, "TOP", posX, posY)
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
end

function sArenaMixin:UpdateHealthBarDRSettings(db, info, val)
    if val ~= nil and info then
        db[info[#info]] = val
    end
    if not db then return end

    for i = 1, self.maxArenaOpponents do
        local frame = self["arena" .. i]
        if frame then
            if not frame.drFramesHB then
                frame:CreateHealthBarDRFrames()
            end
            frame:UpdateHealthBarDRPositions()
        end
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
    local posX = trinketHBSettings.posX or 0
    local posY = trinketHBSettings.posY or 0

    self.TrinketHB:SetSize(size, size)
    self.TrinketHB:ClearAllPoints()
    self.TrinketHB:SetPoint("LEFT", self.HealthBar, "RIGHT", posX + 2, posY)
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
-- DR Immune Glow Effect
-- =============================================

local glowFramePool = {}

local function CreateGlowTexture(parent)
    local glow = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetPoint("TOPLEFT", -3, 3)
    glow:SetPoint("BOTTOMRIGHT", 3, -3)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0)
    return glow
end

function sArenaFrameMixin:SetHealthBarDRGlow(slot, enabled, r, g, b)
    if not self.drFramesHB then return end
    local f = self.drFramesHB[slot]
    if not f then return end

    if not f.GlowTexture then
        f.GlowTexture = CreateGlowTexture(f)
    end

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
