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

local function RenderUnit(unit, now)
    local db = GetSelfDRSettings()
    if not db or not db.enabled then return end

    local w = GetOrCreateWidget(unit)
    local anchor = anchors[unit]
    if not anchor then w:Hide(); return end

    local state = drStates[unit]
    if not state then w:Hide(); return end

    w:ClearAllPoints()
    w:SetPoint("CENTER", anchor, "CENTER", db.posX or 0, db.posY or 0)
    if anchor.GetFrameLevel then
        w:SetFrameLevel((anchor:GetFrameLevel() or 0) + 5)
    end

    local size = db.size or 24
    local spacing = db.spacing or 2
    local grow = db.growthDirection or 3
    local fontSize = db.fontSize or 14

    local shown = 0
    for _, cat in ipairs(CAT_ORDER) do
        if db.categories and db.categories[cat] ~= false then
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

    if shown > 0 then w:Show() else w:Hide() end
end

local function OnTick()
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

    RebuildAnchors()
    ExpireStates(now)

    for _, unit in ipairs(TRACKED_UNITS) do
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

local function GetOrCreateMockPartyFrame()
    if sArenaMixin.selfDRMockFrame then return sArenaMixin.selfDRMockFrame end

    local mock = CreateFrame("Frame", "sArenaSelfDR_MockParty", UIParent, "BackdropTemplate")
    mock:SetSize(120, 32)
    mock:SetFrameStrata("MEDIUM")
    mock:SetFrameLevel(50)

    mock:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    mock:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    mock:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local hp = CreateFrame("StatusBar", nil, mock)
    hp:SetPoint("TOPLEFT", 3, -3)
    hp:SetPoint("BOTTOMRIGHT", -3, 3)
    hp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    hp:SetStatusBarColor(0, 0.8, 0, 1)
    hp:SetMinMaxValues(0, 100)
    hp:SetValue(100)

    local name = hp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("CENTER")
    name:SetText(UnitName("player") or "Player")
    name:SetTextColor(1, 1, 1, 1)

    local label = mock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", mock, "BOTTOM", 0, -2)
    label:SetText("|cff888888" .. (sArenaMixin.L and sArenaMixin.L["SelfDR_MockLabel"] or "Mock Party Frame") .. "|r")

    mock:EnableMouse(true)
    mock:SetMovable(true)
    mock:RegisterForDrag("LeftButton")
    mock:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mock:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    mock:SetPoint("LEFT", UIParent, "CENTER", -300, 0)
    mock:Hide()

    sArenaMixin.selfDRMockFrame = mock
    return mock
end

function sArenaMixin:ShowTestSelfDR()
    local db = self.db and self.db.profile and self.db.profile.selfDR
    if not db or not db.enabled then
        self:HideTestSelfDR()
        return
    end

    -- Use real party frame if available, otherwise create a mock
    local anchor = FindPartyAnchor("player")
    if not anchor then
        local mock = GetOrCreateMockPartyFrame()
        mock:Show()
        anchor = mock
    end
    anchors["player"] = anchor

    local testData = {
        { cat = "stun",    icon = CAT_FALLBACK_ICON.stun,    count = 2, resetIn = 12 },
        { cat = "incap",   icon = CAT_FALLBACK_ICON.incap,   count = 1, resetIn = 8 },
        { cat = "confuse", icon = CAT_FALLBACK_ICON.confuse,  count = 1, resetIn = 14 },
    }

    local now = GetTime()

    drStates["player"] = {}
    for _, td in ipairs(testData) do
        if not db.categories or db.categories[td.cat] ~= false then
            drStates["player"][td.cat] = {
                count = td.count,
                icon = td.icon,
                resetAt = now + td.resetIn,
            }
        end
    end

    local w = GetOrCreateWidget("player")
    w:ClearAllPoints()
    w:SetPoint("CENTER", anchor, "CENTER", db.posX or 0, db.posY or 0)

    local size = db.size or 24
    local spacing = db.spacing or 2
    local grow = db.growthDirection or 3
    local fontSize = db.fontSize or 14
    local shown = 0

    for _, cat in ipairs(CAT_ORDER) do
        if not db.categories or db.categories[cat] ~= false then
            local cs = drStates["player"] and drStates["player"][cat]
            if cs then
                shown = shown + 1
                local f = w.icons[shown]
                if f then
                    f:SetSize(size, size)
                    f:ClearAllPoints()
                    local offset = (shown - 1) * (size + spacing)
                    if grow == 4 then f:SetPoint("CENTER", w, "CENTER", -offset, 0)
                    elseif grow == 3 then f:SetPoint("CENTER", w, "CENTER", offset, 0)
                    elseif grow == 1 then f:SetPoint("CENTER", w, "CENTER", 0, -offset)
                    elseif grow == 2 then f:SetPoint("CENTER", w, "CENTER", 0, offset) end

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
    end
    for i = shown + 1, #w.icons do w.icons[i]:Hide() end
    if shown > 0 then w:Show() end

    if not self.selfDRTestTicker then
        self.selfDRTestTicker = C_Timer.NewTicker(0.5, function()
            if not self.testMode then
                self:HideTestSelfDR()
                return
            end
            local n = GetTime()
            local state = drStates["player"]
            if state then
                local anyActive = false
                for _, cs in pairs(state) do
                    if cs.resetAt and cs.resetAt > n then anyActive = true end
                end
                if not anyActive then
                    for _, td in ipairs(testData) do
                        if not db.categories or db.categories[td.cat] ~= false then
                            state[td.cat] = {
                                count = td.count,
                                icon = td.icon,
                                resetAt = n + td.resetIn,
                            }
                        end
                    end
                end
                -- Update countdown text
                for i = 1, #w.icons do
                    local f = w.icons[i]
                    if f:IsShown() then
                        local catName = CAT_ORDER[i]
                        local cs2 = catName and state[catName]
                        if cs2 and cs2.resetAt then
                            f.text:SetFormattedText("%d", math.ceil(math.max(0, cs2.resetAt - n)))
                        end
                    end
                end
            end
        end)
    end
end

function sArenaMixin:HideTestSelfDR()
    if self.selfDRTestTicker then
        self.selfDRTestTicker:Cancel()
        self.selfDRTestTicker = nil
    end
    drStates["player"] = nil
    local w = widgets["player"]
    if w then w:Hide() end
    if self.selfDRMockFrame then
        self.selfDRMockFrame:Hide()
    end
end
