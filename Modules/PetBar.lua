local L = sArenaMixin.L
local LSM = LibStub("LibSharedMedia-3.0")
local isMidnight = sArenaMixin.isMidnight

local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitName = UnitName
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsUnit = UnitIsUnit
local floor = math.floor

local function IsSec(v)
    return issecretvalue and issecretvalue(v) or false
end

local function CreatePixelBorder(parent, size, r, g, b, a)
    local border = CreateFrame("Frame", nil, parent)
    border:SetPoint("TOPLEFT", -size, size)
    border:SetPoint("BOTTOMRIGHT", size, -size)
    border:SetFrameLevel(parent:GetFrameLevel() + 1)

    local top = border:CreateTexture(nil, "OVERLAY")
    top:SetHeight(size); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    top:SetColorTexture(r, g, b, a)

    local bot = border:CreateTexture(nil, "OVERLAY")
    bot:SetHeight(size); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
    bot:SetColorTexture(r, g, b, a)

    local left = border:CreateTexture(nil, "OVERLAY")
    left:SetWidth(size); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
    left:SetColorTexture(r, g, b, a)

    local right = border:CreateTexture(nil, "OVERLAY")
    right:SetWidth(size); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
    right:SetColorTexture(r, g, b, a)

    border.textures = { top, bot, left, right }

    function border:SetBorderColor(r2, g2, b2, a2)
        for _, tex in ipairs(self.textures) do
            tex:SetColorTexture(r2, g2, b2, a2 or 1)
        end
    end

    function border:SetBorderSize(sz)
        for _, tex in ipairs(self.textures) do
            tex:SetHeight(sz)
            tex:SetWidth(sz)
        end
    end

    return border
end

function sArenaFrameMixin:CreatePetBar()
    if self.PetBar then return end

    local id = self:GetID()
    local petUnit = "arenapet" .. id

    local container = CreateFrame("Frame", "sArenaPetBarContainer" .. id, UIParent)
    container:SetSize(100, 20)
    container:SetFrameStrata("MEDIUM")
    container:SetFrameLevel(self:GetFrameLevel() + 1)
    container:SetAlpha(0)

    -- Background
    local bg = container:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.8)
    container.Background = bg

    -- Health bar
    local healthBar = CreateFrame("StatusBar", "sArenaPetBarHealth" .. id, container)
    healthBar:SetPoint("TOPLEFT", 1, -1)
    healthBar:SetPoint("BOTTOMRIGHT", -1, 1)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetStatusBarColor(0, 1, 0, 1)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    container.HealthBar = healthBar

    local hpUnderlay = healthBar:CreateTexture(nil, "BACKGROUND")
    hpUnderlay:SetAllPoints()
    hpUnderlay:SetColorTexture(0, 0, 0, 0.6)
    container.HealthBar.hpUnderlay = hpUnderlay

    -- Pixel border (default: dark)
    local frameBorder = CreatePixelBorder(container, 1, 0, 0, 0, 1)
    container.FrameBorder = frameBorder

    -- Target highlight border (hidden by default)
    local targetBorder = CreatePixelBorder(container, 2, 1, 1, 1, 1)
    targetBorder:SetPoint("TOPLEFT", -2, 2)
    targetBorder:SetPoint("BOTTOMRIGHT", 2, -2)
    targetBorder:SetFrameLevel(container:GetFrameLevel() + 3)
    targetBorder:Hide()
    container.TargetBorder = targetBorder

    -- Health text
    local healthText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    healthText:SetPoint("RIGHT", healthBar, "RIGHT", -2, 0)
    healthText:SetTextColor(1, 1, 1, 1)
    healthText:SetJustifyH("RIGHT")
    container.HealthText = healthText

    -- Name text
    local nameText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", healthBar, "LEFT", 2, 0)
    nameText:SetTextColor(1, 1, 1, 1)
    nameText:SetJustifyH("LEFT")
    container.NameText = nameText

    -- Secure button (parented to UIParent to avoid combat lockdown)
    local secure = CreateFrame("Button", "sArenaPetBarSecure" .. id, UIParent, "SecureActionButtonTemplate")
    secure:SetAllPoints(container)
    secure:SetAttribute("*type1", "target")
    secure:SetAttribute("*type2", "focus")
    secure:SetAttribute("unit", petUnit)
    secure:RegisterForClicks("AnyDown", "AnyUp")
    secure:SetFrameLevel(container:GetFrameLevel() + 5)
    container.Secure = secure

    -- Event frame
    local eventFrame = CreateFrame("Frame")
    eventFrame.petUnit = petUnit
    eventFrame.parentFrame = self
    eventFrame:RegisterUnitEvent("UNIT_HEALTH", petUnit)
    eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", petUnit)
    eventFrame:RegisterEvent("UNIT_PET")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

    eventFrame:SetScript("OnEvent", function(_, event, eventUnit)
        if event == "PLAYER_TARGET_CHANGED" then
            self:UpdatePetBarTargetHighlight()
            return
        end
        if event == "UNIT_PET" then
            self:RefreshPetBar()
        elseif eventUnit == petUnit then
            pcall(function()
                if not UnitExists(petUnit) or UnitIsDeadOrGhost(petUnit) then
                    container:SetAlpha(0)
                    return
                end
            end)
            if container:GetAlpha() == 0 then
                self:RefreshPetBar()
                return
            end
            pcall(function()
                if event == "UNIT_HEALTH" then
                    local health = UnitHealth(petUnit)
                    if not IsSec(health) and health == 0 then
                        container:SetAlpha(0)
                        return
                    end
                    container.HealthBar:SetValue(health)
                    self:UpdatePetBarHealthText()
                elseif event == "UNIT_MAXHEALTH" then
                    container.HealthBar:SetMinMaxValues(0, UnitHealthMax(petUnit))
                    container.HealthBar:SetValue(UnitHealth(petUnit))
                    self:UpdatePetBarHealthText()
                end
            end)
        end
    end)

    container.eventFrame = eventFrame
    container.petUnit = petUnit
    self.PetBar = container
end

function sArenaFrameMixin:UpdatePetBarTargetHighlight()
    if not self.PetBar or not self.PetBar.TargetBorder then return end
    if self.PetBar:GetAlpha() == 0 then
        self.PetBar.TargetBorder:Hide()
        return
    end

    local petUnit = self.PetBar.petUnit
    local isTarget = false
    pcall(function()
        local result = UnitIsUnit("target", petUnit)
        if not IsSec(result) then
            isTarget = result
        end
    end)

    local db = self.parent and self.parent.db
    local layoutName = db and db.profile.currentLayout
    local petSettings = layoutName and db.profile.layoutSettings[layoutName] and db.profile.layoutSettings[layoutName].petBar

    if isTarget then
        local c = (petSettings and petSettings.targetBorderColor) or {1, 1, 0, 1}
        self.PetBar.TargetBorder:SetBorderColor(c[1], c[2], c[3], c[4] or 1)
        self.PetBar.TargetBorder:Show()
    else
        self.PetBar.TargetBorder:Hide()
    end
end

function sArenaFrameMixin:RefreshPetBar()
    if not self.PetBar then return end

    local db = self.parent.db
    if not db then
        self.PetBar:SetAlpha(0)
        return
    end

    local layoutName = db.profile.currentLayout
    local layoutSettings = db.profile.layoutSettings[layoutName]
    if not layoutSettings or not layoutSettings.petBar or not layoutSettings.petBar.enabled then
        self.PetBar:SetAlpha(0)
        return
    end

    local petUnit = self.PetBar.petUnit
    local exists = UnitExists(petUnit)
    if IsSec(exists) then exists = true end

    if not exists then
        self.PetBar:SetAlpha(0)
        return
    end

    local petSettings = layoutSettings.petBar

    -- Health check
    local skipShow = false
    pcall(function()
        local health = UnitHealth(petUnit)
        local maxHealth = UnitHealthMax(petUnit)
        local dead = UnitIsDeadOrGhost(petUnit)

        local hSec = IsSec(health)
        local mSec = IsSec(maxHealth)
        local dSec = IsSec(dead)

        if not hSec and not dSec and health == 0 and dead then
            self.PetBar:SetAlpha(0)
            skipShow = true
            return
        end

        local safeMax = (not mSec and maxHealth > 0) and maxHealth or 100
        local safeHP = (not hSec) and health or safeMax
        if safeHP == 0 and not (dSec or dead) then safeHP = safeMax end

        self.PetBar.HealthBar:SetMinMaxValues(0, safeMax)
        self.PetBar.HealthBar:SetValue(safeHP)
    end)

    if skipShow then return end

    -- Position
    self.PetBar:SetSize(petSettings.width or 100, petSettings.height or 20)
    self.PetBar:SetScale(petSettings.scale or 1)
    self.PetBar:ClearAllPoints()
    self.PetBar:SetPoint("CENTER", self, "CENTER", petSettings.posX or 0, petSettings.posY or -30)

    -- Border color
    if self.PetBar.FrameBorder then
        local bc = petSettings.borderColor or {0, 0, 0, 1}
        self.PetBar.FrameBorder:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
        local bs = petSettings.borderSize or 1
        self.PetBar.FrameBorder:SetBorderSize(bs)
    end

    -- Name
    local petLabel = L["PetBar_Fallback"] or "Pet"
    pcall(function()
        local name = UnitName(petUnit)
        if name and not IsSec(name) then
            self.PetBar.NameText:SetText(petSettings.showName and name or petLabel)
        else
            self.PetBar.NameText:SetText(petLabel)
        end
        self.PetBar.NameText:Show()
    end)

    -- Color
    pcall(function()
        local c = petSettings.color or {0, 1, 0, 1}
        if petSettings.classColor then
            local _, cls = UnitClass(petUnit)
            if cls and not IsSec(cls) and RAID_CLASS_COLORS[cls] then
                local cc = RAID_CLASS_COLORS[cls]
                self.PetBar.HealthBar:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
                return
            end
        end
        self.PetBar.HealthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    end)

    self.PetBar:SetAlpha(1)
    self:UpdatePetBarTargetHighlight()
end

function sArenaFrameMixin:UpdatePetBarHealthText()
    if not self.PetBar or self.PetBar:GetAlpha() == 0 then return end

    local db = self.parent.db
    if not db then return end

    local layoutName = db.profile.currentLayout
    local layoutSettings = db.profile.layoutSettings[layoutName]
    if not layoutSettings or not layoutSettings.petBar then
        self.PetBar.HealthText:SetText("")
        return
    end

    local petSettings = layoutSettings.petBar
    if not petSettings.showHealthText then
        self.PetBar.HealthText:SetText("")
        return
    end

    pcall(function()
        local petUnit = self.PetBar.petUnit
        local health = UnitHealth(petUnit)
        local maxHealth = UnitHealthMax(petUnit)

        if IsSec(health) or IsSec(maxHealth) then
            self.PetBar.HealthText:SetText("")
            return
        end

        if petSettings.healthTextPercent then
            if isMidnight and UnitHealthPercent and CurveConstants then
                local pct = UnitHealthPercent(petUnit, nil, CurveConstants.ScaleTo100)
                self.PetBar.HealthText:SetFormattedText("%0.f%%", pct or 0)
            elseif maxHealth > 0 then
                self.PetBar.HealthText:SetText(floor(health / maxHealth * 100 + 0.5) .. "%")
            else
                self.PetBar.HealthText:SetText("0%")
            end
        else
            if health >= 1000000 then
                self.PetBar.HealthText:SetText(string.format("%.1fM", health / 1000000))
            elseif health >= 1000 then
                self.PetBar.HealthText:SetText(string.format("%.1fK", health / 1000))
            else
                self.PetBar.HealthText:SetText(tostring(health))
            end
        end
    end)
end

function sArenaFrameMixin:ResetPetBar()
    if not self.PetBar then return end
    self.PetBar:SetAlpha(0)
    self.PetBar:ClearAllPoints()
    self.PetBar.HealthBar:SetStatusBarColor(0, 1, 0, 1)
    self.PetBar.NameText:SetText("")
    self.PetBar.HealthText:SetText("")
    if self.PetBar.TargetBorder then
        self.PetBar.TargetBorder:Hide()
    end
end

function sArenaFrameMixin:ShowTestPetBar()
    if not self.PetBar then return end

    local db = self.parent.db
    if not db then return end

    local layoutName = db.profile.currentLayout
    local layoutSettings = db.profile.layoutSettings[layoutName]
    if not layoutSettings or not layoutSettings.petBar or not layoutSettings.petBar.enabled then
        self.PetBar:SetAlpha(0)
        return
    end

    local petSettings = layoutSettings.petBar
    local id = self:GetID()

    -- Ensure position is set (critical for first-time test mode)
    self.PetBar:SetSize(petSettings.width or 100, petSettings.height or 20)
    self.PetBar:SetScale(petSettings.scale or 1)
    self.PetBar:ClearAllPoints()
    self.PetBar:SetPoint("CENTER", self, "CENTER", petSettings.posX or 0, petSettings.posY or -30)

    self.PetBar.HealthBar:SetMinMaxValues(0, 100)
    self.PetBar.HealthBar:SetValue(id == 1 and 100 or (id == 2 and 65 or 30))

    local testNames = {
        L["PetBar_TestPet1"] or "Wolf",
        L["PetBar_TestPet2"] or "Felguard",
        L["PetBar_TestPet3"] or "Water Elemental",
    }

    if petSettings.showName then
        self.PetBar.NameText:SetText(testNames[id] or "Pet")
    else
        self.PetBar.NameText:SetText(L["PetBar_Fallback"] or "Pet")
    end
    self.PetBar.NameText:Show()

    if petSettings.showHealthText then
        local val = id == 1 and 100 or (id == 2 and 65 or 30)
        if petSettings.healthTextPercent then
            self.PetBar.HealthText:SetText(val .. "%")
        else
            self.PetBar.HealthText:SetText(tostring(val * 1000))
        end
    else
        self.PetBar.HealthText:SetText("")
    end

    local c = petSettings.color or {0, 1, 0, 1}
    self.PetBar.HealthBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)

    -- Border
    if self.PetBar.FrameBorder then
        local bc = petSettings.borderColor or {0, 0, 0, 1}
        self.PetBar.FrameBorder:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
        local bs = petSettings.borderSize or 1
        self.PetBar.FrameBorder:SetBorderSize(bs)
    end

    -- Show target border on first test frame
    if id == 1 and self.PetBar.TargetBorder then
        local tc = petSettings.targetBorderColor or {1, 1, 0, 1}
        self.PetBar.TargetBorder:SetBorderColor(tc[1], tc[2], tc[3], tc[4] or 1)
        self.PetBar.TargetBorder:Show()
    elseif self.PetBar.TargetBorder then
        self.PetBar.TargetBorder:Hide()
    end

    self.PetBar:SetAlpha(1)
end

function sArenaMixin:UpdatePetBarSettings(db, info, val)
    if val ~= nil and info then
        db[info[#info]] = val
    end

    if not db then return end

    for i = 1, self.maxArenaOpponents do
        local frame = self["arena" .. i]
        if frame and frame.PetBar then
            local petBar = frame.PetBar

            petBar:ClearAllPoints()
            petBar:SetSize(db.width or 100, db.height or 20)
            petBar:SetScale(db.scale or 1)
            petBar:SetPoint("CENTER", frame, "CENTER", db.posX or 0, db.posY or -30)

            local bgColor = db.bgColor or {0, 0, 0, 0.8}
            if petBar.Background then
                petBar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.8)
            end
            petBar.HealthBar.hpUnderlay:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.6)

            local texturePath = LSM:Fetch(LSM.MediaType.STATUSBAR, db.texture or "sArena Default")
            if texturePath then
                petBar.HealthBar:SetStatusBarTexture(texturePath)
            end

            if not db.classColor then
                local color = db.color or {0, 1, 0, 1}
                petBar.HealthBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
            end

            if not db.showName then
                petBar.NameText:SetText(L["PetBar_Fallback"] or "Pet")
            end
            petBar.NameText:Show()

            -- Border
            if petBar.FrameBorder then
                local bc = db.borderColor or {0, 0, 0, 1}
                petBar.FrameBorder:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
                local bs = db.borderSize or 1
                petBar.FrameBorder:SetBorderSize(bs)
            end

            if not petBar.dragSetup then
                self:SetupDrag(petBar, petBar, "petBar", "UpdatePetBarSettings")
                petBar.dragSetup = true
            end

            if self.testMode then
                frame:ShowTestPetBar()
            else
                frame:RefreshPetBar()
            end
        end
    end
end
