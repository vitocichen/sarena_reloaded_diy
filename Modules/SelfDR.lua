local L = sArenaMixin.L
local pcall = pcall
local GetTime = GetTime
local C_LossOfControl = C_LossOfControl

local DR_RESET_TIME = 16

local DR_CATS = { "stun", "disorient", "incapacitate", "root", "silence", "knockback", "disarm" }

local DR_ICONS = {
    stun        = "Interface\\Icons\\Ability_Rogue_KidneyShot",
    disorient   = "Interface\\Icons\\Spell_Shadow_Possession",
    incapacitate = "Interface\\Icons\\Spell_Nature_Polymorph",
    root        = "Interface\\Icons\\Spell_Nature_StrangleVines",
    silence     = "Interface\\Icons\\Spell_Shadow_SoulLeech_3",
    knockback   = "Interface\\Icons\\Spell_Nature_CallStorm",
    disarm      = "Interface\\Icons\\Ability_Warrior_Disarm",
}

local LOC_TO_CAT = {
    STUN = "incapacitate", STUN_MECHANIC = "stun",
    FEAR = "disorient", FEAR_MECHANIC = "disorient",
    CHARM = "disorient", CYCLONE = "disorient", POSSESS = "disorient",
    CONFUSE = "incapacitate",
    ROOT = "root", DISARM = "disarm", SILENCE = "silence",
}

local SPELL_OVERRIDE = {
    [31661]  = "disorient", [2094]   = "disorient", [105421] = "disorient",
    [207167] = "disorient", [33786]  = "disorient", [198909] = "disorient",
    [51514]  = "incapacitate", [277784] = "incapacitate", [196942] = "incapacitate",
    [210873] = "incapacitate", [211004] = "incapacitate", [211010] = "incapacitate",
    [211015] = "incapacitate", [269352] = "incapacitate", [309328] = "incapacitate",
    [277778] = "incapacitate",
}

local NON_DR_SPELLS = {
    [87204] = true, [196364] = true, [6789] = true, [100] = true,
    [105771] = true, [78675] = true, [81261] = true, [358861] = true,
    [157997] = true, [370970] = true, [45334] = true,
}

local BASE_ICON_SIZE = 50

local _parentDb = nil
local container = nil
local iconsFrame = nil
local drFrames = {}
local drState = {}
local testTicker = nil

local function GetDB()
    if not _parentDb then return nil end
    return _parentDb.profile and _parentDb.profile.selfDR
end

local function InArena()
    if IsActiveBattlefieldArena then
        local ok, res = pcall(IsActiveBattlefieldArena)
        if ok and res then return true end
    end
    local ok, _, instanceType = pcall(IsInInstance)
    return ok and instanceType == "arena"
end

local function GetLocCategory(locData)
    local spellID = locData and locData.spellID
    if spellID and NON_DR_SPELLS[spellID] then return nil end
    if spellID and SPELL_OVERRIDE[spellID] then return SPELL_OVERRIDE[spellID] end
    local locType = locData and (locData.lockType or locData.locType)
    if not locType then return nil end
    return LOC_TO_CAT[locType]
end

local function GetDRStateText(stacks, isTest)
    if stacks <= 0 then return isTest and "50%" or "" end
    if stacks == 1 then return "50%" end
    return "IMM"
end

local function CreateContainer()
    if container then return end

    container = CreateFrame("Frame", "sArenaSelfDRContainer", UIParent)
    container:SetFrameStrata("HIGH")
    container:SetSize(1, 1)
    container:SetClampedToScreen(true)

    container:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then self:StartMoving() end
    end)
    container:SetScript("OnMouseUp", function(self, btn)
        if btn ~= "LeftButton" then return end
        self:StopMovingOrSizing()
        local db = GetDB()
        if db then
            local point, _, relPoint, x, y = self:GetPoint()
            db.containerPos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    container.title = container:CreateFontString(nil, "OVERLAY")
    container.title:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE")
    container.title:SetPoint("BOTTOM", container, "TOP", 0, 46)
    container.title:SetText(L["Category_SelfDR"] or "Self DR")
    container.title:SetTextColor(1, 0.82, 0, 1)
    container.title:Hide()

    iconsFrame = CreateFrame("Frame", nil, container)
    iconsFrame:SetPoint("LEFT", container, "CENTER", 0, 0)
    iconsFrame:SetSize(BASE_ICON_SIZE, BASE_ICON_SIZE)
    iconsFrame:EnableMouse(false)
    iconsFrame:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" and container:IsMovable() then container:StartMoving() end
    end)
    iconsFrame:SetScript("OnMouseUp", function(_, btn)
        if btn ~= "LeftButton" or not container:IsMovable() then return end
        container:StopMovingOrSizing()
        local db = GetDB()
        if db then
            local point, _, relPoint, x, y = container:GetPoint()
            db.containerPos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)
end

local function CreateIcons()
    if not iconsFrame then return end
    local db = GetDB()
    local scale = db and (db.iconSize or 36) / BASE_ICON_SIZE or 1
    local padding = db and (db.iconPadding or 4) / scale or 4

    for i, cat in ipairs(DR_CATS) do
        if not drFrames[cat] then
            local f = CreateFrame("Button", "sArenaSelfDRIcon_" .. cat, iconsFrame)
            f:SetSize(BASE_ICON_SIZE, BASE_ICON_SIZE)
            f:SetPoint("LEFT", (BASE_ICON_SIZE + padding) * (i - 1), 0)
            f:EnableMouse(false)

            f.icon = f:CreateTexture(nil, "BACKGROUND")
            f.icon:SetAllPoints()
            f.icon:SetTexture(DR_ICONS[cat])

            f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
            f.cd:SetAllPoints()
            f.cd:SetReverse(true)
            f.cd:SetSwipeColor(0, 0, 0, 0.7)
            f.cd:SetHideCountdownNumbers(false)

            pcall(function()
                local closureCat = cat
                f.cd:HookScript("OnCooldownDone", function()
                    if sArenaMixin.selfDRTestMode then return end
                    local st = drState[closureCat]
                    if st and st.isActive then return end
                    ResetCatState(closureCat)
                    f:Hide()
                    SortIcons()
                end)
            end)

            local textFrame = CreateFrame("Frame", nil, f)
            textFrame:SetAllPoints()
            textFrame:SetFrameLevel(f.cd:GetFrameLevel() + 3)
            f.drText = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f.drText:SetPoint("BOTTOM", f, "BOTTOM", 0, 2)
            f.drText:SetFont(f.drText:GetFont(), (db and db.fontSize or 14) / scale, "OUTLINE")

            local border = CreateFrame("Frame", nil, f)
            border:SetPoint("TOPLEFT", -2, 2)
            border:SetPoint("BOTTOMRIGHT", 2, -2)
            border:SetFrameLevel(f:GetFrameLevel() + 2)
            local edges = {}
            local bT = border:CreateTexture(nil, "OVERLAY"); bT:SetHeight(2); bT:SetPoint("TOPLEFT"); bT:SetPoint("TOPRIGHT"); bT:SetColorTexture(1, 0, 0, 1)
            local bB = border:CreateTexture(nil, "OVERLAY"); bB:SetHeight(2); bB:SetPoint("BOTTOMLEFT"); bB:SetPoint("BOTTOMRIGHT"); bB:SetColorTexture(1, 0, 0, 1)
            local bL = border:CreateTexture(nil, "OVERLAY"); bL:SetWidth(2); bL:SetPoint("TOPLEFT"); bL:SetPoint("BOTTOMLEFT"); bL:SetColorTexture(1, 0, 0, 1)
            local bR = border:CreateTexture(nil, "OVERLAY"); bR:SetWidth(2); bR:SetPoint("TOPRIGHT"); bR:SetPoint("BOTTOMRIGHT"); bR:SetColorTexture(1, 0, 0, 1)
            edges = { bT, bB, bL, bR }
            f.immuneBorder = border
            f.immuneEdges = edges
            border:Hide()

            f.cat = cat
            f.sortIndex = i
            f:Hide()
            drFrames[cat] = f
        end
    end
end

function ResetCatState(cat)
    local st = drState[cat]
    if st then
        st.isActive = false
        st.auraIds = nil
        st.lastSeenStartTime = nil
        st.applicationCount = 0
        st.expiresAt = nil
        st.stacks = 0
    end
    local f = drFrames[cat]
    if f then
        f.startTime = nil
        f.drText:SetText("")
        if f.immuneBorder then f.immuneBorder:Hide() end
    end
end

local function ResetAll()
    if sArenaMixin.selfDRTestMode then return end
    for _, cat in ipairs(DR_CATS) do
        ResetCatState(cat)
        local f = drFrames[cat]
        if f then f:Hide() end
    end
    SortIcons()
end

function SortIcons()
    if not iconsFrame then return end
    local db = GetDB()
    local scale = db and (db.iconSize or 36) / BASE_ICON_SIZE or 1
    local padding = db and (db.iconPadding or 4) / scale or 4
    local grow = db and db.growthDirection or "RIGHT"

    local visible = {}
    for _, cat in ipairs(DR_CATS) do
        local f = drFrames[cat]
        if f and f:IsShown() then
            visible[#visible + 1] = f
        end
    end

    table.sort(visible, function(a, b)
        local aT = a.startTime or math.huge
        local bT = b.startTime or math.huge
        if aT == bT then return (a.sortIndex or 0) < (b.sortIndex or 0) end
        return aT < bT
    end)

    local count = math.max(#visible, 1)
    local total = BASE_ICON_SIZE * count + padding * (count - 1)

    iconsFrame:ClearAllPoints()
    if grow == "LEFT" then
        iconsFrame:SetPoint("RIGHT", container, "CENTER", 0, 0)
        iconsFrame:SetSize(total, BASE_ICON_SIZE)
    elseif grow == "UP" then
        iconsFrame:SetPoint("BOTTOM", container, "CENTER", 0, 0)
        iconsFrame:SetSize(BASE_ICON_SIZE, total)
    elseif grow == "DOWN" then
        iconsFrame:SetPoint("TOP", container, "CENTER", 0, 0)
        iconsFrame:SetSize(BASE_ICON_SIZE, total)
    else
        iconsFrame:SetPoint("LEFT", container, "CENTER", 0, 0)
        iconsFrame:SetSize(total, BASE_ICON_SIZE)
    end

    iconsFrame:SetScale(scale)

    for idx, f in ipairs(visible) do
        f:ClearAllPoints()
        if grow == "LEFT" then
            if idx == 1 then f:SetPoint("RIGHT", iconsFrame, "RIGHT", 0, 0)
            else f:SetPoint("RIGHT", visible[idx - 1], "LEFT", -padding, 0) end
        elseif grow == "UP" then
            if idx == 1 then f:SetPoint("BOTTOM", iconsFrame, "BOTTOM", 0, 0)
            else f:SetPoint("BOTTOM", visible[idx - 1], "TOP", 0, padding) end
        elseif grow == "DOWN" then
            if idx == 1 then f:SetPoint("TOP", iconsFrame, "TOP", 0, 0)
            else f:SetPoint("TOP", visible[idx - 1], "BOTTOM", 0, -padding) end
        else
            if idx == 1 then f:SetPoint("LEFT", iconsFrame, "LEFT", 0, 0)
            else f:SetPoint("LEFT", visible[idx - 1], "RIGHT", padding, 0) end
        end
    end
end

local function StartDRWindow(cat, stackOverride)
    local f = drFrames[cat]
    if not f then return end
    local db = GetDB()

    local st = drState[cat]
    if not st then
        st = { isActive = false, auraIds = nil, lastSeenStartTime = nil, applicationCount = 0, expiresAt = nil, stacks = 0 }
        drState[cat] = st
    end

    local now = GetTime()
    f.startTime = now

    local stacks = stackOverride or (st.stacks + 1)
    stacks = math.max(1, math.min(2, stacks))

    st.stacks = stacks
    st.applicationCount = stacks
    st.expiresAt = now + DR_RESET_TIME

    f.drText:SetText(GetDRStateText(stacks, false))
    local showText = db and db.showDRText ~= false
    f.drText:SetShown(showText)

    if f.immuneBorder then
        f.immuneBorder:SetShown(stacks >= 2)
    end

    f:Show()
    f.cd:SetCooldown(now, DR_RESET_TIME)
    f.cd:SetSwipeColor(0, 0, 0, 0.7)
    SortIcons()
end

local function UpdateDRs()
    if sArenaMixin.selfDRTestMode then return end
    if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataByUnit) then return end
    local db = GetDB()
    if not db then return end

    local activeDRs = {}
    local locEntries = {}

    for i = 1, 10 do
        local ok, data = pcall(C_LossOfControl.GetActiveLossOfControlDataByUnit, "player", i)
        if not ok or not data then break end
        locEntries[#locEntries + 1] = data
    end

    local spellsWithNonRoot = {}
    for _, data in ipairs(locEntries) do
        local cat = GetLocCategory(data)
        if cat and cat ~= "root" and data.spellID then
            spellsWithNonRoot[data.spellID] = true
        end
    end

    for _, data in ipairs(locEntries) do
        local cat = GetLocCategory(data)
        if cat and not (cat == "root" and data.spellID and spellsWithNonRoot[data.spellID]) then
            if not activeDRs[cat] then
                activeDRs[cat] = { auraIds = {}, startTime = 0 }
            end
            if data.auraInstanceID then
                activeDRs[cat].auraIds[data.auraInstanceID] = true
            end
            if data.startTime and data.startTime > activeDRs[cat].startTime then
                activeDRs[cat].startTime = data.startTime
            end
        end
    end

    local now = GetTime()

    for _, cat in ipairs(DR_CATS) do
        if not drState[cat] then
            drState[cat] = { isActive = false, auraIds = nil, lastSeenStartTime = nil, applicationCount = 0, expiresAt = nil, stacks = 0 }
        end
        local st = drState[cat]

        local tracked = db.categories and db.categories[cat] ~= false
        if not tracked then
            if st.isActive or st.stacks > 0 or st.expiresAt then ResetCatState(cat) end
            st.isActive = false
            local f = drFrames[cat]; if f then f:Hide() end
        else
            local active = activeDRs[cat]
            local isActive = active ~= nil
            local newApp = false

            if isActive then
                if not st.isActive then
                    newApp = true
                else
                    for id in pairs(active.auraIds) do
                        if not st.auraIds or not st.auraIds[id] then newApp = true; break end
                    end
                    if not newApp and active.startTime > (st.lastSeenStartTime or 0) + 0.05 then
                        newApp = true
                    end
                end
            end

            if newApp then
                local count = math.min(st.applicationCount + 1, 2)
                st.applicationCount = count
                if count > st.stacks then
                    st.stacks = count
                    local f = drFrames[cat]
                    if f and f.immuneBorder then f.immuneBorder:SetShown(count >= 2) end
                end
                local f = drFrames[cat]
                if f and f.cd then f.cd:SetCooldown(0, 0) end
            end

            if st.isActive and not isActive then
                if st.applicationCount > 0 then
                    StartDRWindow(cat, st.applicationCount)
                end
            end

            st.isActive = isActive
            st.auraIds = isActive and active.auraIds or nil
            st.lastSeenStartTime = isActive and active.startTime or nil

            local f = drFrames[cat]
            if isActive then
                if f then
                    if st.stacks > 0 then f:Show() else f:Hide() end
                    if f.drText then f.drText:Hide() end
                end
            else
                local expAt = st.expiresAt
                local inWindow = expAt and expAt > now
                if f then
                    if inWindow then f:Show() else f:Hide() end
                end
                if expAt and not inWindow then ResetCatState(cat) end
            end
        end
    end

    SortIcons()
end

local function ApplyConfig()
    if not container then return end
    local db = GetDB()
    if not db then return end

    local pos = db.containerPos or { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 }
    container:ClearAllPoints()
    container:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 200)

    local scale = (db.iconSize or 36) / BASE_ICON_SIZE
    local fontSize = (db.fontSize or 14) / scale

    for _, cat in ipairs(DR_CATS) do
        local f = drFrames[cat]
        if f then
            f:SetSize(BASE_ICON_SIZE, BASE_ICON_SIZE)
            f.cd:SetHideCountdownNumbers(not (db.showCountdown ~= false))
            if f.drText then
                f.drText:SetFont(f.drText:GetFont(), fontSize, "OUTLINE")
                f.drText:SetShown(db.showDRText ~= false)
            end
            if not (db.categories and db.categories[cat] ~= false) then
                f:Hide()
            end
        end
    end

    SortIcons()
end

local function ApplyZoneState()
    local db = GetDB()
    if not db or not db.enabled then return end

    ResetAll()
    if InArena() then
        sArenaMixin._selfDREventFrame:RegisterEvent("UNIT_AURA")
    else
        sArenaMixin._selfDREventFrame:UnregisterEvent("UNIT_AURA")
    end
end

local eventFrame = CreateFrame("Frame")
sArenaMixin._selfDREventFrame = eventFrame
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        ApplyZoneState()
    elseif event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
        ResetAll()
    elseif event == "UNIT_AURA" then
        if arg1 == "player" then UpdateDRs() end
    end
end)

function sArenaMixin:EnableSelfDR()
    _parentDb = self.db
    CreateContainer()
    CreateIcons()
    ApplyConfig()

    local db = GetDB()
    if db and db.enabled then
        container:Show()
        ApplyZoneState()
    else
        if container then container:Hide() end
        eventFrame:UnregisterEvent("UNIT_AURA")
        ResetAll()
    end
end

function sArenaMixin:ShowTestSelfDR()
    _parentDb = _parentDb or self.db
    CreateContainer()
    CreateIcons()
    ApplyConfig()

    sArenaMixin.selfDRTestMode = true
    container:SetMovable(true)
    container:EnableMouse(true)
    container:SetFrameStrata("TOOLTIP")
    if iconsFrame then iconsFrame:EnableMouse(true) end
    if container.title then container.title:Show() end
    container:Show()

    local function playOnce()
        local db = GetDB()
        if not db then return end
        local now = GetTime()
        for i, cat in ipairs(DR_CATS) do
            local f = drFrames[cat]
            if f then
                local tracked = db.categories and db.categories[cat] ~= false
                if tracked then
                    f:Show()
                    f.cd:SetCooldown(now, DR_RESET_TIME)
                    f.cd:SetSwipeColor(0, 0, 0, 0.7)
                    f.startTime = now + (i * 0.001)
                    if i == 1 then
                        f.drText:SetText("IMM")
                        f.drText:SetShown(db.showDRText ~= false)
                        if f.immuneBorder then f.immuneBorder:Show() end
                    else
                        f.drText:SetText("50%")
                        f.drText:SetShown(db.showDRText ~= false)
                        if f.immuneBorder then f.immuneBorder:Hide() end
                    end
                else
                    f:Hide()
                end
            end
        end
        SortIcons()
    end

    if testTicker then testTicker:Cancel() end
    testTicker = C_Timer.NewTicker(DR_RESET_TIME, playOnce)
    playOnce()
end

function sArenaMixin:HideTestSelfDR()
    sArenaMixin.selfDRTestMode = false
    if testTicker then testTicker:Cancel(); testTicker = nil end

    if container then
        container:SetMovable(false)
        container:EnableMouse(false)
        container:SetFrameStrata("HIGH")
        if iconsFrame then iconsFrame:EnableMouse(false) end
        if container.title then container.title:Hide() end
    end

    ResetAll()
    UpdateDRs()
    ApplyConfig()

    local db = GetDB()
    if db and db.enabled then
        if container then container:Show() end
    else
        if container then container:Hide() end
    end
end

SLASH_SELFDR1 = "/selfdr"
SlashCmdList["SELFDR"] = function(msg)
    local cmd = msg and msg:trim():lower() or ""
    if cmd == "test" then
        if sArenaMixin.selfDRTestMode then
            sArenaMixin:HideTestSelfDR()
        else
            sArenaMixin:ShowTestSelfDR()
        end
    else
        local db = GetDB()
        print("[SelfDR] enabled=" .. tostring(db and db.enabled) .. " arena=" .. tostring(InArena()))
    end
end
