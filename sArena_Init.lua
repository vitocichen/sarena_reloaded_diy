sArenaMixin = {}
sArenaFrameMixin = {}

local gameVersion = select(1, GetBuildInfo())
sArenaMixin.isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
sArenaMixin.isMidnight = gameVersion:match("^12")
sArenaMixin.isMoP = gameVersion:match("^5%.")
sArenaMixin.isWrath = gameVersion:match("^3%.")
sArenaMixin.isTBC = gameVersion:match("^2%.")

sArenaMixin.addonTitle = "|T135884:13:13|t sArena |cffff8000Reloaded|r v1.0.0 |cffff8800DIY:|r |cff00ff96DK-\229\167\156\228\184\150\231\166\187(\231\135\131\231\131\167\228\185\139\229\136\131)|r"
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
        trinketOnHealthBar = {
            enabled = false,
            size = 20,
            posX = 0,
            posY = 0,
        },
        selfDR = {
            enabled = false,
            posX = 0,
            posY = 0,
            size = 24,
            spacing = 2,
            growthDirection = 3,
            fontSize = 14,
            categories = {
                stun = true,
                incap = true,
                confuse = true,
                root = true,
            },
        },
    }
}