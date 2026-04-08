sArenaMixin = {}
sArenaFrameMixin = {}

local gameVersion = select(1, GetBuildInfo())
sArenaMixin.isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
sArenaMixin.isMidnight = gameVersion:match("^12")
sArenaMixin.isMoP = gameVersion:match("^5%.")
sArenaMixin.isWrath = gameVersion:match("^3%.")
sArenaMixin.isTBC = gameVersion:match("^2%.")

sArenaMixin.addonName = "|T135884:13:13|t sArena |cffff8000Reloaded|r"
sArenaMixin.addonTitle = sArenaMixin.addonName .. " v1.0.4"
sArenaMixin.popupHeader = "\n" .. sArenaMixin.addonName .. "\n\n"
sArenaMixin.layouts = {}
sArenaMixin.defaultSettings = {
    profile = {
        currentLayout = "Gladiuish",
        classColors = true,
        --classColorFrameTexture = (BetterBlizzFramesDB and BetterBlizzFramesDB.classColorFrameTexture) or nil,
        showNames = true,
        hidePowerText = true,
        showDecimalsDR = true,
        showDecimalsClassIcon = true,
        decimalThreshold = 6,
        colorDRCooldownText = false,
        --darkMode = (BetterBlizzFramesDB and BetterBlizzFramesDB.darkModeUi) or C_AddOns.IsAddOnLoaded("FrameColor") or nil,
        forceShowTrinketOnHuman = not sArenaMixin.isRetail and true or nil,
        shadowSightTimer = (sArenaMixin.isTBC or sArenaMixin.isWrath) and true or nil,
        trinketSoundName = "Lossa Trinket",
        trinketSoundFileID = 0,
        healerTrinketSoundName = "Lossa Trinket",
        healerTrinketSoundFileID = 0,
        trinketSoundChannel = "Master",
        darkModeValue = 0.2,
        desaturateTrinketCD = true,
        desaturateDispelCD = true,
        darkModeDesaturate = true,
        statusText = {
            alwaysShow = true,
            formatNumbers = true,
        },
        trinketColors = {
            available = { 0, 1, 0 },
            used = { 1, 0, 0 },
        },
        castBarColors = {
            standard = { 1.0, 0.7, 0.0, 1 },
            channel = { 0.0, 1.0, 0.0, 1 },
            uninterruptable = { 0.7, 0.7, 0.7, 1 },
            interruptNotReady = { 1.0, 0.0, 0.0, 1 },
        },
        layoutSettings = {},
        invertClassIconCooldown = true,
        rightClickFocus = true,
        clickAttributes = {
            ["Left"] = { button = "1", action = "target" },
            ["Right"] = { button = "2", action = "focus" },
        },
        trinketOnHealthBar = {
            enabled = false,
            size = 20,
            posX = 0,
            posY = 0,
        },
        nameplateDRZones = {
            enableInArena = true,
            enableInWorld = true,
            enableInBattleground = true,
            enableInDungeon = true,
        },
        nameplateDRCategories = {
            stun = true,
            incap = true,
            fear = true,
            root = true,
            disarm = true,
            silence = true,
        },
        nameplateDRMaxIcons = 5,
        selfDR = {
            enabled = false,
            enableInArena = true,
            enableInBattleground = true,
            enableInWorld = true,
            iconSize = 36,
            iconPadding = 4,
            fontSize = 14,
            growthDirection = "RIGHT",
            showDRText = true,
            showCountdown = true,
            containerPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 },
            categories = {
                stun = true,
                disorient = true,
                incapacitate = true,
                root = true,
                silence = false,
                knockback = false,
                disarm = false,
            },
        },
    }
}