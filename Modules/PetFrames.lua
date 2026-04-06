-- Pet Frames Module for sArena Reloaded
-- 为竞技场对手的宠物（arenapet1-3）添加血条
-- 参考 GladiusEx PetBar 模块架构

local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local LSM = LibStub("LibSharedMedia-3.0")

-- 宠物血条默认颜色（绿色）
local PET_BAR_COLOR = { r = 0.0, g = 0.7, b = 0.2 }
local PET_BAR_BG_COLOR = { r = 0, g = 0, b = 0, a = 0.7 }

-- 独立的宠物事件监听框架（不干扰主框架的事件注册）
local petEventFrame = CreateFrame("Frame")
petEventFrame:Hide()
petEventFrame.unitFrames = {} -- 映射: petUnit -> arena frame

----------------------------------------------------------------------
-- 创建宠物框体
----------------------------------------------------------------------
function sArenaFrameMixin:CreatePetFrame()
    if self.PetFrame then return end

    local petFrame = CreateFrame("Frame", nil, self)
    petFrame:SetFrameStrata("MEDIUM")
    petFrame:SetFrameLevel(self:GetFrameLevel() + 1)
    petFrame:Hide()

    -- 背景
    local bg = petFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(PET_BAR_BG_COLOR.r, PET_BAR_BG_COLOR.g, PET_BAR_BG_COLOR.b, PET_BAR_BG_COLOR.a)
    petFrame.bg = bg

    -- 血条
    local healthBar = CreateFrame("StatusBar", nil, petFrame)
    healthBar:SetAllPoints()
    healthBar:SetMinMaxValues(0, 1)
    healthBar:SetValue(1)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetStatusBarColor(PET_BAR_COLOR.r, PET_BAR_COLOR.g, PET_BAR_COLOR.b)
    petFrame.HealthBar = healthBar

    -- 血量文字（可选）
    local healthText = healthBar:CreateFontString(nil, "OVERLAY")
    healthText:SetFontObject("GameFontNormalSmall")
    healthText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
    healthText:SetTextColor(1, 1, 1, 1)
    healthText:Hide()
    petFrame.HealthText = healthText

    -- 像素边框
    local borderSize = 1
    local borders = {}
    for i = 1, 4 do
        borders[i] = petFrame:CreateTexture(nil, "OVERLAY")
        borders[i]:SetColorTexture(0, 0, 0, 1)
    end
    -- 上
    borders[1]:SetPoint("TOPLEFT", petFrame, "TOPLEFT", -borderSize, borderSize)
    borders[1]:SetPoint("TOPRIGHT", petFrame, "TOPRIGHT", borderSize, borderSize)
    borders[1]:SetHeight(borderSize)
    -- 下
    borders[2]:SetPoint("BOTTOMLEFT", petFrame, "BOTTOMLEFT", -borderSize, -borderSize)
    borders[2]:SetPoint("BOTTOMRIGHT", petFrame, "BOTTOMRIGHT", borderSize, -borderSize)
    borders[2]:SetHeight(borderSize)
    -- 左
    borders[3]:SetPoint("TOPLEFT", petFrame, "TOPLEFT", -borderSize, borderSize)
    borders[3]:SetPoint("BOTTOMLEFT", petFrame, "BOTTOMLEFT", -borderSize, -borderSize)
    borders[3]:SetWidth(borderSize)
    -- 右
    borders[4]:SetPoint("TOPRIGHT", petFrame, "TOPRIGHT", borderSize, borderSize)
    borders[4]:SetPoint("BOTTOMRIGHT", petFrame, "BOTTOMRIGHT", borderSize, -borderSize)
    borders[4]:SetWidth(borderSize)
    petFrame.borders = borders

    self.PetFrame = petFrame
    self.petUnit = "arenapet" .. self:GetID()
end

----------------------------------------------------------------------
-- 更新宠物框体的可见性和血量
----------------------------------------------------------------------
function sArenaFrameMixin:UpdatePetFrame()
    if not self.PetFrame then return end

    local db = self.parent.db
    if not db or not db.profile.showPetFrames then
        self.PetFrame:Hide()
        return
    end

    local petUnit = self.petUnit
    if petUnit and UnitExists(petUnit) then
        local hp = UnitHealth(petUnit)
        local hpMax = UnitHealthMax(petUnit)

        if hpMax > 0 then
            self.PetFrame.HealthBar:SetMinMaxValues(0, hpMax)
            self.PetFrame.HealthBar:SetValue(hp)

            if self.PetFrame.HealthText and db.profile.petFrameShowHealth then
                local pct = math.floor((hp / hpMax) * 100)
                self.PetFrame.HealthText:SetText(pct .. "%")
                self.PetFrame.HealthText:Show()
            else
                self.PetFrame.HealthText:Hide()
            end
        end

        self.PetFrame:Show()
    else
        self.PetFrame:Hide()
    end
end

----------------------------------------------------------------------
-- 重置宠物框体
----------------------------------------------------------------------
function sArenaFrameMixin:ResetPetFrame()
    if not self.PetFrame then return end
    self.PetFrame:Hide()
    self.PetFrame.HealthBar:SetMinMaxValues(0, 1)
    self.PetFrame.HealthBar:SetValue(1)
    if self.PetFrame.HealthText then
        self.PetFrame.HealthText:SetText("")
        self.PetFrame.HealthText:Hide()
    end
end

----------------------------------------------------------------------
-- 应用宠物框体设置（位置、大小、纹理）
----------------------------------------------------------------------
function sArenaMixin:UpdatePetFrameSettings()
    local db = self.db
    if not db then return end

    local layoutdb = db.profile.layoutSettings[db.profile.currentLayout]
    local petSettings = layoutdb and layoutdb.petBar or {}
    local enabled = db.profile.showPetFrames

    local width = petSettings.width or 80
    local height = petSettings.height or 8
    local posX = petSettings.posX or 0
    local posY = petSettings.posY or -2

    for i = 1, self.maxArenaOpponents do
        local frame = self["arena" .. i]
        if not frame then return end

        if not frame.PetFrame then
            frame:CreatePetFrame()
        end

        local petFrame = frame.PetFrame
        petFrame:SetSize(width, height)
        petFrame:ClearAllPoints()
        petFrame:SetPoint("TOP", frame.HealthBar, "BOTTOM", posX, posY)

        -- 应用纹理
        local texKey = layoutdb and layoutdb.textures and layoutdb.textures.generalStatusBarTexture
        if texKey then
            local texPath = LSM:Fetch(LSM.MediaType.STATUSBAR, texKey)
            if texPath then
                petFrame.HealthBar:SetStatusBarTexture(texPath)
            end
        end

        -- 使用主人职业颜色
        if db.profile.petFrameClassColor and frame.class then
            local color = RAID_CLASS_COLORS[frame.class]
            if color then
                petFrame.HealthBar:SetStatusBarColor(color.r, color.g, color.b)
            else
                petFrame.HealthBar:SetStatusBarColor(PET_BAR_COLOR.r, PET_BAR_COLOR.g, PET_BAR_COLOR.b)
            end
        else
            petFrame.HealthBar:SetStatusBarColor(PET_BAR_COLOR.r, PET_BAR_COLOR.g, PET_BAR_COLOR.b)
        end

        -- 显示血量文字
        if petFrame.HealthText then
            petFrame.HealthText:SetShown(db.profile.petFrameShowHealth or false)
        end

        if not enabled then
            petFrame:Hide()
        end
    end
end

----------------------------------------------------------------------
-- 独立宠物事件框架的事件处理
-- 使用独立框架监听宠物血量事件，避免干扰主框架的 RegisterUnitEvent
-- 注意：不用 RegisterUnitEvent 因为多次调用会覆盖前一次的单位过滤
-- 改用 RegisterEvent + 手动过滤 petUnit
----------------------------------------------------------------------
petEventFrame:SetScript("OnEvent", function(self, event, unit)
    if not unit then return end
    local frame = self.unitFrames[unit]
    if frame then
        frame:UpdatePetFrame()
    end
end)

----------------------------------------------------------------------
-- 宠物事件注册（进入竞技场时调用）
-- 在父框架上注册 UNIT_PET
-- 在独立框架上注册 UNIT_HEALTH / UNIT_MAXHEALTH（全局事件，手动过滤）
----------------------------------------------------------------------
function sArenaMixin:RegisterPetEvents()
    if not self.db or not self.db.profile.showPetFrames then return end

    self:RegisterEvent("UNIT_PET")

    -- 建立 petUnit -> arenaFrame 映射
    for i = 1, self.maxArenaOpponents do
        local frame = self["arena" .. i]
        if frame and frame.petUnit then
            petEventFrame.unitFrames[frame.petUnit] = frame
        end
    end

    -- 使用全局事件注册（不限制单位数量），在 OnEvent 中手动过滤
    petEventFrame:RegisterEvent("UNIT_HEALTH")
    petEventFrame:RegisterEvent("UNIT_MAXHEALTH")

    -- 初始检测：检查当前已存在的宠物
    for i = 1, self.maxArenaOpponents do
        local frame = self["arena" .. i]
        if frame then
            frame:UpdatePetFrame()
        end
    end
end

function sArenaMixin:UnregisterPetEvents()
    self:UnregisterEvent("UNIT_PET")

    -- 清理独立事件框架
    petEventFrame:UnregisterAllEvents()
    wipe(petEventFrame.unitFrames)
end

----------------------------------------------------------------------
-- 处理 UNIT_PET 事件（宠物出现/消失）
----------------------------------------------------------------------
function sArenaMixin:OnUnitPet(unit)
    -- unit 是拥有者（arena1, arena2 等）
    for i = 1, self.maxArenaOpponents do
        if unit == "arena" .. i then
            local frame = self["arena" .. i]
            if frame then
                frame:UpdatePetFrame()
            end
            break
        end
    end
end

----------------------------------------------------------------------
-- 在 ARENA_OPPONENT_UPDATE (seen) 时也检查宠物
----------------------------------------------------------------------
function sArenaFrameMixin:CheckPetOnUpdate()
    if not self.parent.db or not self.parent.db.profile.showPetFrames then return end
    -- 延迟一帧检查，确保宠物单位数据已就绪
    C_Timer.After(0.1, function()
        if self.PetFrame then
            self:UpdatePetFrame()
        end
    end)
end

----------------------------------------------------------------------
-- 测试模式：显示宠物框体
----------------------------------------------------------------------
function sArenaMixin:TestPetFrames()
    local db = self.db
    if not db or not db.profile.showPetFrames then return end

    local numUnits = math.min(self.testUnits or self.maxArenaOpponents, self.maxArenaOpponents)

    for i = 1, numUnits do
        local frame = self["arena" .. i]
        if not frame then return end

        if not frame.PetFrame then
            frame:CreatePetFrame()
        end

        local petFrame = frame.PetFrame

        -- 测试模式在第1和第3框架显示宠物（模拟猎人/术士有宠物的情况）
        if i == 1 or i == 3 then
            petFrame.HealthBar:SetMinMaxValues(0, 100)
            local testHp = (i == 1) and 100 or 65
            petFrame.HealthBar:SetValue(testHp)

            if petFrame.HealthText and db.profile.petFrameShowHealth then
                petFrame.HealthText:SetText(testHp .. "%")
                petFrame.HealthText:Show()
            end

            petFrame:Show()
        else
            petFrame:Hide()
        end
    end
end

----------------------------------------------------------------------
-- 隐藏所有宠物框体（退出竞技场时调用）
----------------------------------------------------------------------
function sArenaMixin:HideAllPetFrames()
    for i = 1, self.maxArenaOpponents do
        local frame = self["arena" .. i]
        if frame then
            frame:ResetPetFrame()
        end
    end
end
