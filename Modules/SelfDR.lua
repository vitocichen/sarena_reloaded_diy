local L = sArenaMixin.L

local DR_RESET_TIME = 16
local SCAN_INTERVAL = 0.05
local REAPPLY_WINDOW = 6.0

local CAT_ORDER = { "stun", "incap", "confuse", "root" }
local CAT_FALLBACK_ICON = {
    stun    = 132298,
    incap   = 136071,
    confuse = 136183,
    root    = 136100,
}

local LOC_TYPE_TO_CAT = {
    STUN = "incap", STUN_MECHANIC = "stun",
    FEAR = "incap", FEAR_MECHANIC = "confuse",
    CHARM = "confuse", CYCLONE = "confuse", CONFUSE = "confuse",
    ROOT = "root", SILENCE = "root", DISARM = "root",
}

local TRACKED_UNITS = { "player", "party1", "party2", "party3", "party4" }

local drStates = {}
local activeLoC = {}
local reapplyWindow = {}
local widgets = {}
local anchors = {}
local ticker
local selfDREnabled = false

local function InArena()
    if IsActiveBattlefieldArena then
        local ok, res = pcall(IsActiveBattlefieldArena)
        if ok and res then return true end
    end
    local ok, _, instanceType = pcall(IsInInstance)
    return ok and instanceType == "arena"
end

local function BumpStage(unit, cat, now)
    drStates[unit] = drStates[unit] or {}
    local cs = drStates[unit][cat] or { count = 0, icon = CAT_FALLBACK_ICON[cat] }
    if cs.resetAt and now >= cs.resetAt then cs.count = 0 end
    cs.count = math.min(3, cs.count + 1)
    cs.icon = CAT_FALLBACK_ICON[cat]
    cs.resetAt = nil
    drStates[unit][cat] = cs
end

local function StartResetTimer(unit, cat, now)
    if not (drStates[unit] and drStates[unit][cat]) then return end
    drStates[unit][cat].resetAt = now + DR_RESET_TIME
end

local function ScanLoC(unit, now)
    if not (C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataByUnit) then return end

    local current = {}
    for index = 1, 10 do
        local ok, data = pcall(C_LossOfControl.GetActiveLossOfControlDataByUnit, unit, index)
        if not ok or not data then break end

        local cat = data.locType and LOC_TYPE_TO_CAT[data.locType]
        if cat then
            current[cat] = current[cat] or {}
            local id = data.auraInstanceID
            if type(id) == "number" then
                current[cat][id] = true
            else
                current[cat]._active = true
            end
        end
    end

    activeLoC[unit] = activeLoC[unit] or {}
    local prev = activeLoC[unit]

    for _, cat in ipairs(CAT_ORDER) do
        local curSet = current[cat]
        local prevSet = prev[cat]
        local prevActive = prevSet ~= nil
        local curActive = curSet ~= nil

        if curActive then
            if not prevActive then
                BumpStage(unit, cat, now)
                reapplyWindow[unit] = reapplyWindow[unit] or {}
                reapplyWindow[unit][cat] = { untilTime = now + REAPPLY_WINDOW, bumped = false }
            else
                for id in pairs(curSet) do
                    if id ~= "_active" and (not prevSet or not prevSet[id]) then
                        BumpStage(unit, cat, now)
                        local rw = reapplyWindow[unit]
                        if rw and rw[cat] then rw[cat].bumped = true end
                        break
                    end
                end
            end
            prev[cat] = curSet
        else
            if prevActive then
                StartResetTimer(unit, cat, now)
                local rw = reapplyWindow[unit]
                if rw then rw[cat] = nil end
            end
            prev[cat] = nil
        end
    end
end

local function ExpireStates(now)
    for unit, cats in pairs(drStates) do
        local empty = true
        for cat, cs in pairs(cats) do
            if cs.resetAt and now >= cs.resetAt then
                cats[cat] = nil
            else
                empty = false
            end
        end
        if empty then drStates[unit] = nil end
    end
end

local function ResetAll()
    wipe(drStates)
    wipe(activeLoC)
    wipe(reapplyWindow)
    for _, w in pairs(widgets) do
        if w and w.Hide then w:Hide() end
    end
end

local function GetOrCreateWidget(unit)
    if widgets[unit] then return widgets[unit] end

    local w = CreateFrame("Frame", "sArenaSelfDR_" .. unit, UIParent)
    w:SetFrameStrata("HIGH")
    w:SetFrameLevel(100)
    w:SetSize(1, 1)
    w:Hide()

    w.icons = {}
    for i = 1, 4 do
        local f = CreateFrame("Frame", nil, w)
        f:SetSize(24, 24)
        f:Hide()

        f.tex = f:CreateTexture(nil, "ARTWORK")
        f.tex:SetAllPoints()

        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.7)

        f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        f.cd:SetAllPoints()
        f.cd:SetDrawEdge(false)
        f.cd:SetDrawSwipe(true)
        f.cd:SetReverse(true)
        f.cd:SetSwipeColor(0, 0, 0, 0.7)
        f.cd:SetHideCountdownNumbers(true)

        local borderFrame = CreateFrame("Frame", nil, f)
        borderFrame:SetPoint("TOPLEFT", -1, 1)
        borderFrame:SetPoint("BOTTOMRIGHT", 1, -1)
        borderFrame:SetFrameLevel(f:GetFrameLevel() + 2)
        f.borderTextures = {}
        local sides = {
            { "TOPLEFT", "TOPRIGHT", nil, 1 },
            { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        }
        local bTop = borderFrame:CreateTexture(nil, "OVERLAY")
        bTop:SetHeight(1); bTop:SetPoint("TOPLEFT"); bTop:SetPoint("TOPRIGHT")
        bTop:SetColorTexture(0, 1, 0, 1)
        local bBot = borderFrame:CreateTexture(nil, "OVERLAY")
        bBot:SetHeight(1); bBot:SetPoint("BOTTOMLEFT"); bBot:SetPoint("BOTTOMRIGHT")
        bBot:SetColorTexture(0, 1, 0, 1)
        local bLeft = borderFrame:CreateTexture(nil, "OVERLAY")
        bLeft:SetWidth(1); bLeft:SetPoint("TOPLEFT"); bLeft:SetPoint("BOTTOMLEFT")
        bLeft:SetColorTexture(0, 1, 0, 1)
        local bRight = borderFrame:CreateTexture(nil, "OVERLAY")
        bRight:SetWidth(1); bRight:SetPoint("TOPRIGHT"); bRight:SetPoint("BOTTOMRIGHT")
        bRight:SetColorTexture(0, 1, 0, 1)
        f.borderTextures = { bTop, bBot, bLeft, bRight }

        local textHolder = CreateFrame("Frame", nil, f)
        textHolder:SetAllPoints()
        textHolder:SetFrameLevel(f.cd:GetFrameLevel() + 3)
        f.text = textHolder:CreateFontString(nil, "OVERLAY")
        f.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        f.text:SetPoint("CENTER", 0, 0)

        w.icons[i] = f
    end

    widgets[unit] = w
    return w
end

local function SetIconBorderColor(icon, r, g, b, a)
    if not icon.borderTextures then return end
    for _, tex in ipairs(icon.borderTextures) do
        tex:SetColorTexture(r, g, b, a or 1)
    end
end

local function FindPartyAnchor(unit)
    if unit == "player" then
        local pf = _G.PartyFrame
        if pf and pf.PlayerFrame and pf.PlayerFrame.IsVisible and pf.PlayerFrame:IsVisible() then
            return pf.PlayerFrame
        end
        for i = 1, 5 do
            local f = _G["CompactPartyFrameMember" .. i]
            if f and f.IsVisible and f:IsVisible() then
                local fu = f.unit or f.unitToken or (f.GetAttribute and f:GetAttribute("unit"))
                if fu == "player" or fu == "party0" then return f end
            end
        end
    end

    local idx = unit:match("^party(%d)$")
    if idx then
        local f = _G["CompactPartyFrameMember" .. (tonumber(idx) + 1)]
        if f and f.IsVisible and f:IsVisible() then return f end
        local pf = _G.PartyFrame
        if pf and pf.PartyMemberFramePool then
            for member in pf.PartyMemberFramePool:EnumerateActive() do
                if member and member.IsVisible and member:IsVisible() then
                    local fu = member.unit or member.unitToken or (member.GetAttribute and member:GetAttribute("unit"))
                    if fu == unit then return member end
                end
            end
        end
    end
    return nil
end

local function RebuildAnchors()
    wipe(anchors)
    for _, unit in ipairs(TRACKED_UNITS) do
        if unit == "player" or UnitExists(unit) then
            anchors[unit] = FindPartyAnchor(unit)
        end
    end
end

local function GetSelfDRSettings()
    local parent = sArenaMixin.db
    if not parent then return nil end
    return parent.profile.selfDR
end

local function IsSelfOnlyMode()
    local db = GetSelfDRSettings()
    return db and db.trackMode == 1
end

local function SetupSelfOnlyDrag(w)
    if w.dragSetup then return end
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", function(self) self:StartMoving() end)
    w:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = GetSelfDRSettings()
        if db then
            local cx, cy = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            db.selfPosX = cx - ux
            db.selfPosY = cy - uy
        end
    end)
    w.dragSetup = true
end

local function ResizeWidgetToFitIcons(w, shown, size, spacing, grow)
    if shown <= 0 then return end
    local total = shown * size + (shown - 1) * spacing
    if grow == 3 or grow == 4 then
        w:SetSize(total, size)
    else
        w:SetSize(size, total)
    end
end

local function DisableSelfOnlyDrag(w)
    if not w.dragSetup then return end
    w:EnableMouse(false)
    w:SetMovable(false)
    w:SetScript("OnDragStart", nil)
    w:SetScript("OnDragStop", nil)
    w.dragSetup = nil
end

local function RenderUnit(unit, now)
    local db = GetSelfDRSettings()
    if not db or not db.enabled then return end

    local selfOnly = IsSelfOnlyMode()
    if selfOnly and unit ~= "player" then return end

    local w = GetOrCreateWidget(unit)

    local state = drStates[unit]
    if not state then w:Hide(); return end

    w:ClearAllPoints()
    if selfOnly and unit == "player" then
        w:SetPoint("CENTER", UIParent, "CENTER", db.selfPosX or 0, db.selfPosY or 200)
        w:SetFrameStrata("HIGH")
        w:SetFrameLevel(200)
        SetupSelfOnlyDrag(w)
    else
        local anchor = anchors[unit]
        if not anchor then w:Hide(); return end
        w:SetPoint("CENTER", anchor, "CENTER", db.posX or 0, db.posY or 0)
        if anchor.GetFrameLevel then
            w:SetFrameLevel((anchor:GetFrameLevel() or 0) + 5)
        end
        DisableSelfOnlyDrag(w)
    end

    local size = db.size or 24
    local spacing = db.spacing or 2
    local grow = db.growthDirection or 3
    local fontSize = db.fontSize or 14

    local shown = 0
    for _, cat in ipairs(CAT_ORDER) do
        if not db.categories or db.categories[cat] ~= false then
            local cs = state[cat]
            if cs and cs.resetAt and cs.resetAt > now and not (activeLoC[unit] and activeLoC[unit][cat]) then
                shown = shown + 1
                local f = w.icons[shown]
                if f then
                    f:SetSize(size, size)
                    f:ClearAllPoints()

                    local offset = (shown - 1) * (size + spacing)
                    if grow == 4 then
                        f:SetPoint("CENTER", w, "CENTER", -offset, 0)
                    elseif grow == 3 then
                        f:SetPoint("CENTER", w, "CENTER", offset, 0)
                    elseif grow == 1 then
                        f:SetPoint("CENTER", w, "CENTER", 0, -offset)
                    elseif grow == 2 then
                        f:SetPoint("CENTER", w, "CENTER", 0, offset)
                    end

                    f.tex:SetTexture(cs.icon)
                    f.cd:SetCooldown(cs.resetAt - DR_RESET_TIME, DR_RESET_TIME)
                    f.text:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
                    local remain = cs.resetAt - now
                    f.text:SetFormattedText("%d", math.ceil(math.max(0, remain)))

                    if cs.count <= 1 then
                        SetIconBorderColor(f, 0, 1, 0, 1)
                    else
                        SetIconBorderColor(f, 1, 0, 0, 1)
                    end
                    f:Show()
                end
            end
        end
    end

    for i = shown + 1, #w.icons do
        w.icons[i]:Hide()
    end

    ResizeWidgetToFitIcons(w, shown, size, spacing, grow)
    if shown > 0 then w:Show() else w:Hide() end
end

local function OnTick()
    if sArenaMixin.selfDRTestMode then return end

    local db = GetSelfDRSettings()
    if not db or not db.enabled then
        ResetAll()
        return
    end

    if not InArena() then
        ResetAll()
        return
    end

    local now = GetTime()
    local selfOnly = IsSelfOnlyMode()

    if not selfOnly then
        RebuildAnchors()
    end
    ExpireStates(now)

    local unitsToScan = selfOnly and { "player" } or TRACKED_UNITS
    for _, unit in ipairs(unitsToScan) do
        if unit == "player" or UnitExists(unit) then
            ScanLoC(unit, now)
            RenderUnit(unit, now)
        else
            local w = widgets[unit]
            if w then w:Hide() end
            drStates[unit] = nil
            activeLoC[unit] = nil
        end
    end
end

local function OnUnitAura(unit, updateInfo)
    if not unit then return end
    if IsSelfOnlyMode() and unit ~= "player" then return end
    local isTracked = false
    for _, u in ipairs(TRACKED_UNITS) do
        if u == unit then isTracked = true; break end
    end
    if not isTracked then return end

    local db = GetSelfDRSettings()
    if not db or not db.enabled then return end
    if not InArena() then return end

    local now = GetTime()

    if updateInfo and updateInfo.updatedAuraInstanceIDs then
        local rw = reapplyWindow[unit]
        local prev = activeLoC[unit]
        if rw and prev then
            local updated = {}
            for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
                if type(id) == "number" then updated[id] = true end
            end
            for cat, st in pairs(rw) do
                if st and not st.bumped and now <= st.untilTime then
                    local prevSet = prev[cat]
                    if prevSet then
                        for id in pairs(prevSet) do
                            if id ~= "_active" and updated[id] then
                                BumpStage(unit, cat, now)
                                st.bumped = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    ScanLoC(unit, now)
    ExpireStates(now)
    RenderUnit(unit, now)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_ENTERING_WORLD" then
        local db = GetSelfDRSettings()
        if not db or not db.enabled then return end

        if InArena() then
            if not ticker then
                ticker = C_Timer.NewTicker(SCAN_INTERVAL, OnTick)
            end
        else
            ResetAll()
            wipe(anchors)
            if ticker then ticker:Cancel(); ticker = nil end
        end
    elseif event == "UNIT_AURA" then
        OnUnitAura(arg1, arg2)
    end
end)

function sArenaMixin:EnableSelfDR()
    local db = self.db and self.db.profile and self.db.profile.selfDR
    if db and db.enabled then
        if not ticker then
            ticker = C_Timer.NewTicker(SCAN_INTERVAL, OnTick)
        end
    else
        if ticker then ticker:Cancel(); ticker = nil end
        ResetAll()
        wipe(anchors)
    end
end

local TEST_UNITS = { "player", "party1", "party2" }
local testMockFrames = {}
local testMockContainer = nil

local function CreateMockTestFrames()
    if testMockContainer then return end

    local _, playerClass = UnitClass("player")
    local colour = RAID_CLASS_COLORS[playerClass] or NORMAL_FONT_COLOR

    -- Exact MiniCC dimensions and style
    local width, height = 144, 72
    local padding = 10

    testMockContainer = CreateFrame("Frame", "sArenaSelfDR_TestContainer", UIParent)
    testMockContainer:SetSize(width + padding * 2, height * 3 + padding * 2)
    testMockContainer:SetClampedToScreen(true)
    testMockContainer:EnableMouse(true)
    testMockContainer:SetMovable(true)
    testMockContainer:RegisterForDrag("LeftButton")
    testMockContainer:SetScript("OnDragStart", function(s) s:StartMoving() end)
    testMockContainer:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    testMockContainer:SetPoint("CENTER", UIParent, "CENTER", -450, 0)
    testMockContainer:Hide()

    for i = 1, 3 do
        local f = CreateFrame("Frame", "sArenaSelfDR_TestFrame" .. i, testMockContainer, "BackdropTemplate")
        f:SetSize(width, height)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        f:SetBackdropColor(colour.r, colour.g, colour.b, 0.9)
        f:SetBackdropBorderColor(0, 0, 0, 1)

        f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.Text:SetPoint("CENTER")
        f.Text:SetText(("party%d"):format(i))
        f.Text:SetTextColor(1, 1, 1)

        f:ClearAllPoints()
        f:SetPoint("TOP", testMockContainer, "TOP", 0, (i - 1) * -height - padding)

        f.unit = TEST_UNITS[i]
        testMockFrames[i] = f
    end
end

function sArenaMixin:ShowTestSelfDR()
    local selfDRdb = self.db and self.db.profile and self.db.profile.selfDR
    if not selfDRdb or not selfDRdb.enabled then
        self:HideTestSelfDR()
        return
    end

    self.selfDRTestMode = true

    -- Stop the real ticker to prevent interference
    if ticker then ticker:Cancel(); ticker = nil end

    CreateMockTestFrames()

    local selfOnly = (selfDRdb.trackMode == 1)
    local testUnits = selfOnly and { "player" } or TEST_UNITS

    if not selfOnly then
        local hasRealFrames = false
        for _, unit in ipairs(testUnits) do
            local a = FindPartyAnchor(unit)
            if a then hasRealFrames = true; break end
        end
        if not hasRealFrames then
            testMockContainer:Show()
            for _, f in ipairs(testMockFrames) do f:Show() end
        end
    end

    local testData = {
        { cat = "stun",    icon = CAT_FALLBACK_ICON.stun,    count = 2, resetIn = 14 },
        { cat = "incap",   icon = CAT_FALLBACK_ICON.incap,   count = 1, resetIn = 10 },
        { cat = "confuse", icon = CAT_FALLBACK_ICON.confuse,  count = 1, resetIn = 16 },
    }

    local testStates = {}

    local function RefreshTestDR()
        local now = GetTime()
        local size = selfDRdb.size or 24
        local spacing = selfDRdb.spacing or 2
        local grow = selfDRdb.growthDirection or 3
        local fontSize = selfDRdb.fontSize or 14

        for idx, unit in ipairs(testUnits) do
            if not testStates[unit] then testStates[unit] = {} end
            local state = testStates[unit]

            local anyActive = false
            for _, cs in pairs(state) do
                if cs.resetAt and cs.resetAt > now then anyActive = true end
            end
            if not anyActive then
                for _, td in ipairs(testData) do
                    state[td.cat] = {
                        count = td.count,
                        icon = td.icon,
                        resetAt = now + td.resetIn + (idx - 1) * 2,
                    }
                end
            end

            local w = GetOrCreateWidget(unit)
            w:ClearAllPoints()
            w:SetFrameStrata("HIGH")
            w:SetFrameLevel(200)

            if selfOnly then
                w:SetPoint("CENTER", UIParent, "CENTER", selfDRdb.selfPosX or 0, selfDRdb.selfPosY or 200)
                SetupSelfOnlyDrag(w)
            else
                local anchor = FindPartyAnchor(unit)
                if not anchor and testMockFrames[idx] then anchor = testMockFrames[idx] end
                if not anchor then return end
                w:SetPoint("CENTER", anchor, "CENTER", selfDRdb.posX or 0, selfDRdb.posY or 0)
                DisableSelfOnlyDrag(w)
            end

            local shown = 0
            for _, cat in ipairs(CAT_ORDER) do
                local cs = state[cat]
                if cs and cs.resetAt and cs.resetAt > now then
                    shown = shown + 1
                    local f = w.icons[shown]
                    if f then
                        f:SetSize(size, size)
                        f:ClearAllPoints()
                        local offset = (shown - 1) * (size + spacing)
                        if grow == 4 then f:SetPoint("CENTER", w, "CENTER", -offset, 0)
                        elseif grow == 3 then f:SetPoint("CENTER", w, "CENTER", offset, 0)
                        elseif grow == 1 then f:SetPoint("CENTER", w, "CENTER", 0, -offset)
                        else f:SetPoint("CENTER", w, "CENTER", 0, offset) end

                        f.tex:SetTexture(cs.icon)
                        f.cd:SetCooldown(cs.resetAt - DR_RESET_TIME, DR_RESET_TIME)
                        f.text:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
                        f.text:SetFormattedText("%d", math.ceil(math.max(0, cs.resetAt - now)))
                        if cs.count <= 1 then
                            SetIconBorderColor(f, 0, 1, 0, 1)
                        else
                            SetIconBorderColor(f, 1, 0, 0, 1)
                        end
                        f:Show()
                    end
                end
            end
            for i = shown + 1, #w.icons do w.icons[i]:Hide() end
            ResizeWidgetToFitIcons(w, shown, size, spacing, grow)
            if shown > 0 then w:Show() else w:Hide() end
        end
    end

    RefreshTestDR()

    if self.selfDRTestTicker then self.selfDRTestTicker:Cancel() end
    self.selfDRTestTicker = C_Timer.NewTicker(0.5, function()
        if not self.testMode and not self.selfDRTestMode then
            self:HideTestSelfDR()
            return
        end
        RefreshTestDR()
    end)
end

function sArenaMixin:HideTestSelfDR()
    self.selfDRTestMode = nil
    if self.selfDRTestTicker then
        self.selfDRTestTicker:Cancel()
        self.selfDRTestTicker = nil
    end
    for _, unit in ipairs(TEST_UNITS) do
        local w = widgets[unit]
        if w then
            for _, icon in ipairs(w.icons) do icon:Hide() end
            w:Hide()
        end
    end
    if testMockContainer then testMockContainer:Hide() end
    for _, f in ipairs(testMockFrames) do f:Hide() end

    -- Restart real ticker if selfDR is enabled and not in test
    local selfDRdb = sArenaMixin.db and sArenaMixin.db.profile and sArenaMixin.db.profile.selfDR
    if selfDRdb and selfDRdb.enabled and InArena() then
        if not ticker then
            ticker = C_Timer.NewTicker(SCAN_INTERVAL, OnTick)
        end
    end
end
