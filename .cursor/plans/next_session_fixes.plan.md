---
name: ""
overview: ""
todos: []
isProject: false
---

# Next Session: Bug Fixes & UI Restructure

## Context

This plan documents all pending issues from the current session. Reference this file in the next chat window with `@next_session_fixes.plan.md`.

All code is at: `C:\Users\vitocichen\Desktop\mcu_fw\wow\sArena_Reloaded-v2.4.3\sArena_Reloaded\`

## Issue 1: Nameplate DR — Opacity and Border Size Not Working in Test Mode

`ShowTestNameplateDR()` in `Modules/HealthBarDR.lua` does not apply `alpha` or `borderSize` settings to test frames. Need to add:

- `f:SetAlpha(db.alpha or 1.0)` for each test DR frame
- Border thickness update using `SetHeight`/`SetWidth` on border textures

Reference the real `UpdateNameplateDRPositions()` in the same file (around line 367-390) which already does this correctly. Copy the same logic into `ShowTestNameplateDR()` (around line 525).

## Issue 2: Nameplate DR — Font Size Still Not Working in Test Mode

The `CDText` field on nameplate DR frames is obtained from `cd:GetRegions()` during `CreateNameplateDRFrames()`. But the Cooldown's built-in FontString may not exist until the first `SetCooldown` call triggers it. So `f.CDText` might be nil at creation time.

**Fix**: In `ShowTestNameplateDR`, after `SetCooldown`, re-acquire the CDText if nil:

```lua
if not f.CDText then
    for _, region in next, { f.Cooldown:GetRegions() } do
        if region:GetObjectType() == "FontString" then
            f.CDText = region; break
        end
    end
end
```

## Issue 3: Config UI Restructure — Replace Dropdown with Two Checkboxes

Current: A dropdown "递减显示位置" with options "仅框体/仅名条/框体+名条"

**Change to**: Two separate toggle checkboxes:

1. **"框体递减"** group (rename from current "递减效果") — contains a "启用" toggle + all existing frame DR settings
2. **"姓名版递减"** group (rename from "名条上的递减") — contains a "启用" toggle + all nameplate DR settings

Both can be independently enabled/disabled. Replace `drAnchorMode` (number 1/2/3) with two booleans:

- `drFrameEnabled` (default true) — show DR on arena frame
- `drNameplateEnabled` (default false) — show DR on nameplate

### Files to modify:

- `Config.lua` — restructure optionsTable: rename groups, add enable toggles, remove dropdown
- `sArena_Init.lua` — may need to add default booleans
- `Modules/Functions.lua` — Midnight hooks check `drFrameEnabled`/`drNameplateEnabled` instead of `drAnchorMode`
- `Modules/DiminishingReturns.lua` — FindDR checks new booleans
- `Modules/TestMode.lua` — test mode checks new booleans
- `Modules/HealthBarDR.lua` — `UpdateNameplateDRPositions` checks new boolean
- All 9 `Layouts/*.lua` — replace `drAnchorMode = 1` with `drFrameEnabled = true, drNameplateEnabled = false`
- `Locales/enUS.lua` and `zhCN.lua` — update strings

### Locale changes:

- "递减效果" → "框体递减"
- "名条上的递减" → "姓名版递减"
- Add "启用框体递减" and "启用姓名版递减" toggle labels
- Remove dropdown-related strings

## Issue 4: Pet Bar Still Not Showing in Arena

Last debug output shows `hp=111419/325109 dead=false` but `hasPoints=false visible=false`. Code was wrapped in pcall to catch errors. Next test should show either:

- Green `[PetBar OK]` — code completed, frame should be visible
- Red `[PetBar ERROR]` — specific error message

If `[PetBar OK]` shows with `parentShown=false` or `parentAlpha=0`, the issue is that the arena frame itself is not visible when the pet bar tries to show.

### Potential root cause:

On Midnight, arena frames might use `SetAlpha(0)` for "hidden" state instead of `Hide()`. The PetBar is a child frame, so it inherits the alpha. If `parentAlpha=0`, the pet bar would be invisible even though `IsShown()=true`.

**Fix if parentAlpha=0**: Parent PetBar to `UIParent` instead of `self` (the arena frame), and manually sync position to the arena frame. Similar to how nameplate DR frames are parented to UIParent.

## Issue 5: Remove Debug Prints Before Release

The following debug prints need to be removed once testing is done:

- `[PetBar SHOW]` in `Modules/PetBar.lua` ~line 131-135
- `[PetBar OK]` in `Modules/PetBar.lua` ~line 193-198
- `[PetBar ERROR]` in `Modules/PetBar.lua` ~line 187-189
- `[NP-DR]` in `Modules/HealthBarDR.lua` ~line 347-352
- `[sArena DR Probe]` in `Modules/Functions.lua` ~line 489-494

## Priority Order

1. **Issue 3** (Config restructure) — biggest user-facing change
2. **Issue 1+2** (Test mode fixes) — quick fixes
3. **Issue 4** (Pet bar) — depends on user test results
4. **Issue 5** (Remove debug) — after all issues resolved

