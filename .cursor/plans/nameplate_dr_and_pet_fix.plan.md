# Nameplate DR Rewrite + Pet Frame Fix

## Context

User tested sArena Reloaded DIY in arena and found two critical issues:
1. The "healthbar DR" feature anchors to sArena frame's HealthBar, but user wants it on **nameplates** (enemy head nameplate that moves with character), exactly like MidnightDR
2. Pet frame doesn't show in actual arena matches even when enabled

## Issue 1: Nameplate DR (MUST REWRITE)

### Current (wrong) implementation
- `Modules/HealthBarDR.lua` creates mirror DR frames anchored to `self.HealthBar` (sArena arena frame healthbar)
- This shows DR icons on the static sArena frame, NOT on the moving nameplate above enemies
- User explicitly confirmed they want nameplate DR, like MidnightDR's Arena module

### What needs to happen
Rewrite `HealthBarDR.lua` to anchor DR to **nameplates** using `C_NamePlate.GetNamePlates()`.

**Reference: MidnightDR's Arena.lua approach:**
- File: `C:\Users\vitocichen\Desktop\mcu_fw\wow\MidnightDR\Modules\Arena.lua`
- `GetNameplateAnchorForUnit(unit)` — finds nameplate for arena unit via GUID/composite key matching
- `ApplyLayoutDR(i, anchor)` — positions DR mirror frames relative to the nameplate UnitFrame
- DR frames parented to UIParent (prevents nameplate clipping), scale synced via `GetEffectiveScale()`
- Handles `NAME_PLATE_UNIT_ADDED` / `NAME_PLATE_UNIT_REMOVED` events
- Has `issecretvalue` protection for GUID matching, falls back to composite key (honor+class+race)

**Key code patterns from MidnightDR:**
```lua
-- Anchor finding (Arena.lua ~353)
local function GetNameplateAnchorForUnit(unit)
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    -- Match via GUID, then UnitIsUnit, then composite key fallback
end

-- Layout application (Arena.lua ~687)
local function ApplyLayoutDR(i, anchor)
    root:SetParent(UIParent)
    root:SetPoint("CENTER", anchor, "CENTER", offX, offY)
    local us = anchor:GetEffectiveScale() or 1
    local ps = UIParent:GetEffectiveScale() or 1
    root:SetScale(us / ps)
end
```

**Implementation plan:**
1. Delete current `HealthBarDR.lua` anchor-to-sArena-healthbar approach
2. Create new nameplate DR system:
   - Event frame listening for NAME_PLATE_UNIT_ADDED/REMOVED + PLAYER_TARGET_CHANGED + UPDATE_MOUSEOVER_UNIT
   - Nameplate anchor cache per arena unit
   - Mirror frames parented to UIParent with scale sync
   - On Midnight: hook existing `SpellDiminishStatusTray` and mirror to nameplate position
   - On non-Midnight: sync from existing FindDR results
3. Config: anchor mode dropdown should be "Arena Frame Only" / "Nameplate Only" / "Both"
4. Settings: position/size/spacing relative to nameplate anchor

**Files to modify:**
- `Modules/HealthBarDR.lua` — full rewrite
- `Modules/Functions.lua` — Midnight hooks update nameplate mirrors
- `Modules/DiminishingReturns.lua` — non-Midnight FindDR update nameplate mirrors
- `Config.lua` — rename labels, adjust settings
- `sArena.lua` — event registration for nameplate events
- `Locales/*.lua` — update strings

## Issue 2: Pet Frame Not Showing in Arena

### Symptoms
- Pet bar enabled in settings
- In actual arena match, enemy has pet (e.g. Hunter pet, Warlock demon)
- Pet bar does not appear

### Likely causes to investigate

1. **UNIT_PET event not firing** — The event frame registers `UNIT_PET` as a global event and `UNIT_HEALTH`/`UNIT_MAXHEALTH` for `arenapetN`. Check if `UNIT_PET` fires correctly on Midnight.

2. **UnitExists("arenapet1") returning secret value** — On Midnight, `UnitExists` can return a secret value. The code checks `if UnitExists(petUnit)` which might fail if the return is secret.

3. **RefreshPetBar timing** — Maybe `RefreshPetBar` runs before the pet data is available.

4. **Event frame creation timing** — The event frame registers for `arenapet1` health events at OnLoad, but on Midnight the arena unit might not be resolved yet.

### Debug approach
Add debug prints in `RefreshPetBar` and the event handler to check:
```lua
print("[PetBar] RefreshPetBar called, unit=" .. self.unit .. " petUnit=" .. tostring(self.PetBar.petUnit))
print("[PetBar] UnitExists=" .. tostring(UnitExists(petUnit)))
print("[PetBar] enabled=" .. tostring(layoutSettings.petBar.enabled))
```

### Files
- `Modules/PetBar.lua` — add debug prints, check issecretvalue on UnitExists

## Also: Existing DR secret value probe

There's still a debug print in `Modules/Functions.lua` line 489-494 (the `[sArena DR Probe]` print). User should test this in arena and report whether textures are secret values. The results determine whether DR icon customization on Midnight is possible.

Plan file: `.cursor/plans/dr_icon_test_and_implement.plan.md`

## Priority Order

1. **Pet frame fix** — smaller scope, add debug prints first
2. **Nameplate DR rewrite** — large scope, reference MidnightDR Arena.lua
3. **Config restructure** — rename "血条DR" to "名条DR", move settings inside DR tab
