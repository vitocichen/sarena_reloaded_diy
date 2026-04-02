---
name: ""
overview: ""
todos: []
isProject: false
---

# DR Icon Customization on Midnight - Test & Implement Plan

## Background Context

Users requested GladiusEx-style DR icon customization on sArena_Reloaded (Midnight 12.0):

- Custom static icons per DR category (e.g. always show Polymorph icon for Incapacitate)
- Category filtering (enable/disable specific DR types)
- Per-class / per-spec icon and category overrides

The original author intentionally disabled these features on Midnight with `disabled = function() return isMidnight end` in Config.lua (lines 5617 and 5727).

## The Secret Value Problem

Midnight 12.0 introduced "Secret Values" - a black-box system where combat data passed to addons cannot be read/compared/stored, only forwarded to other API calls. Evidence from mini-cc addon shows `issecretvalue()` checks everywhere (UnitExists, UnitGUID, C_Spell.IsSpellCrowdControl all return secrets).

The core question: In the existing SetTexture hook (`Modules/Functions.lua` line 489):

```lua
hooksecurefunc(blizzDRFrame.Icon, "SetTexture", function(_, texture)
    sArenaDRFrame.Icon:SetTexture(texture)  -- this works (passthrough)
    -- But can we READ/COMPARE `texture`?
end)
```

If `texture` is a secret value, we CANNOT use it as a table key or compare it, so the reverse-lookup approach fails entirely.

## Current State: Debug Probe Added

A debug print was added to `Modules/Functions.lua` in the SetTexture hook:

```lua
print("[sArena DR Probe] texture=" .. tostring(texture) .. " isSecret=" .. tostring(isSecret) .. " type=" .. type(texture))
```

This prints to chat whenever a DR icon updates in arena. It does NOT affect normal functionality.

## Test Instructions

1. Enter an arena match (any bracket)
2. Wait for any CC/DR to trigger on enemy frames
3. Check the chat window for `[sArena DR Probe]` messages
4. Note down the output for at least 2-3 different DR triggers

### Expected outputs:

**If NOT secret (feature CAN be implemented):**

```
[sArena DR Probe] texture=132298 isSecret=false type=number
```

Texture is a normal number (spell icon file ID). We can compare and lookup.

**If IS secret (feature CANNOT be implemented):**

```
[sArena DR Probe] texture=userdata: 0x... isSecret=true type=userdata
```

OR the `tostring()` might error/return garbage. The `issecretvalue` will return true.

## Decision Path

### IF texture is NOT secret (isSecret=false, type=number):

Implement the full DR customization feature:

**Files to modify:**

1. `**Modules/Functions.lua`** (Midnight DR hook section, after line 434):
  - Add `BuildTextureToCategory()` - builds reverse map from `sArenaMixin.drList`: for each spellID, call `GetSpellTexture(spellID)` to get texture ID, map it to the DR category
  - Add `GetMidnightDRIconOverride(self, category, originalTexture)` - checks `drStaticIcons`, `drStaticIconsPerSpec`, `drStaticIconsPerClass`, `drIcons`, `drIconsPerSpec`, `drIconsPerClass` in priority order, returns override texture or original
  - Add `IsMidnightDRCategoryEnabled(self, category)` - checks `drCategoriesPerSpec`, `drCategoriesPerClass`, `drCategories` in priority order
  - Modify SetTexture hook: lookup category from texture via reverse map, apply icon override and category filter
  - Modify Show hook: skip showing if category is disabled
  - Modify Hide hook: clear `.drCategory` tag
2. `**Config.lua**`:
  - Line 5617: Remove `disabled = function() return isMidnight end` from categories group
  - Line 5727: Remove `disabled = function() return isMidnight end` from dynamicIcons group
  - Add Midnight-specific description notes in both groups explaining texture-matching limitation
3. `**Locales/enUS.lua**` and `**Locales/zhCN.lua**`:
  - Add `L["DR_MidnightCategoryNote"]` - explains texture matching ~95% accuracy
  - Add `L["DR_MidnightIconNote"]` - explains how to use static icons on Midnight
4. **Remove the debug probe** from `Modules/Functions.lua` (the `[sArena DR Probe]` print)

### IF texture IS secret (isSecret=true):

1. **Remove the debug probe** from `Modules/Functions.lua`
2. **No other changes** - the `disabled = isMidnight` restrictions are correct
3. Reply to users: Midnight's Secret Values prevent DR icon customization. This is Blizzard's intentional design - addons can display DR frames but cannot identify their content.

## Non-Midnight Note

On non-Midnight versions (11.x, TBC, Wrath, MoP), DR customization already works perfectly. The `FindDR` function in `Modules/DiminishingReturns.lua` handles everything via COMBAT_LOG_EVENT_UNFILTERED with full spellID accuracy. The `disabled = isMidnight` only affects Midnight users.

## Reference: Key Code Locations

- DR hook initialization: `Modules/Functions.lua` line 436 (`InitializeMidnightDRFrames`)
- SetTexture hook: `Modules/Functions.lua` line 489
- DR data (spellID -> category): `Data/DRs/DrList_Retail.lua` (`sArenaMixin.drList`)
- Default DR icons: `Data/DRs/DrList_Retail.lua` line 21 (`sArenaMixin.defaultSettings.profile.drIcons`)
- Config disabled checks: `Config.lua` lines 5617, 5727
- Non-Midnight DR logic: `Modules/DiminishingReturns.lua` line 97 (`FindDR`)
- Secret value examples: `mini-cc/src/Utils/SpellCache.lua`, `mini-cc/src/Core/UnitAuraWatcher.lua`

