-- Steal An Egg - Miracle Hub Core Configuration
-- File: core.lua

return function()
    local ctx = {
    GAME_NAME = "Steal An Egg",
    PLACE_ID = 107778070777162,
    SEARCH_ITEMS = {"egg", "farm", "hunt", "steal", "travel", "hatch", "equip"},
    ACTIVE_LOOP_KEYS = {},
    ACTIVE_LOOP_LABELS = {},
    
    -- UI Configuration
    PAGES_CONFIG = {
        {name = "Home", key = "home", icon = "🏠"},
        {name = "Auto Farm", key = "autofarm", icon = "⛏️"},
        {name = "Egg Tracker", key = "eggs", icon = "🥚"},
        {name = "Movement", key = "movement", icon = "🚶"},
        {name = "Settings", key = "settings", icon = "⚙️"}
    },
    
    -- Remote/Network References
    Data = {
        PACKETS = {
            AdminAbuse_GetActiveEvents = "ReplicatedStorage.Network.AdminAbuse_GetActiveEvents",
            AdminAbuse_GetEventNames = "ReplicatedStorage.Network.AdminAbuse_GetEventNames",
            ExperienceEventPrompt_MarkSeen = "ReplicatedStorage.Network.Experience Event Prompt: Mark Seen",
            ExperienceEventPrompt_GetState = "ReplicatedStorage.Network.Experience Event Prompt: Get State",
        },
        
        GUARDS = {
            GuardTutorial_RequestRuntimeState = "ReplicatedStorage.Network.GuardTutorial: RequestRuntimeState",
            GuardTutorial_GetState = "ReplicatedStorage.Network.ServerLuck:GetState",
        },
        
        GEAR_DATA = {
            -- Egg types and their properties will be populated from runtime discovery
            RARITIES = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical"},
            TYPES = {"Normal", "Dragon", "Demonic", "Great Bloom", "Sakura"}
        },
        
        SAFE_ZONES = {
            -- Areas that won't trigger guard validation
            SPAWN = true
        }
    },
    
    -- Network Endpoints (will be resolved at runtime)
    NETWORK_ENDPOINTS = {
        ADMIN_ABUSE = "AdminAbuse",
        GUARD_TUTORIAL = "GuardTutorial",
        EXPERIENCE_EVENTS = "ExperienceEventPrompt",
        BACKPACK = "Backpack",
        OFFLINE_ASSETS = "OfflineAssets",
        ACTIVE_ASSETS = "ActiveAssets"
    },
    
    -- Movement trust settings to avoid anti-cheat detection
    TRUST_SETTINGS = {
        ENABLE_SMOOTH_MOVEMENT = true,
        MAX_WALK_SPEED_VARIATION = 0.5,      -- Max walkspeed change per second
        MAX_JUMP_HEIGHT_VARIATION = 1.2,      -- Max jump height deviation
        MIN_TRUST_BUILD_TIME = 5,             -- Seconds before any automation can start
        SMOOTH_TRAVEL_SPEED = 1.5,            -- Travel speed multiplier (not full fly)
        ANTI_AFK_INTERVAL = 30,               -- Seconds between valid movements
    },
    
    -- Game state tracking
    States = {
        enabled = false,
        autoFarm = false,
        autoHunt = false,
        autoCollect = false,
        smoothTravel = false,
        antiAFK = false,
        stealthMode = true,           -- Critical for undetectability
        trustBuildingComplete = false,
        showNotifications = true,       -- Enable/disable UI notifications
    },
    
    -- Color Palette (required by UI framework)
    Colors = {
        Background = Color3.fromRGB(10, 13, 16),      -- gunmetal black
        BackgroundLight = Color3.fromRGB(18, 22, 27), -- gunmetal panel
        BackgroundLighter = Color3.fromRGB(26, 31, 38), -- gunmetal secondary
        Surface = Color3.fromRGB(32, 38, 46),
        SurfaceLight = Color3.fromRGB(40, 48, 58),
        Border = Color3.fromRGB(30, 37, 45),          -- gunmetal border
        BorderLight = Color3.fromRGB(40, 100, 95),    -- teal-tinted border
        TextPrimary = Color3.fromRGB(209, 213, 219),
        TextSecondary = Color3.fromRGB(148, 155, 165),
        TextMuted = Color3.fromRGB(113, 113, 122),
        Accent = Color3.fromRGB(77, 214, 201),        -- lime-400
        Success = Color3.fromRGB(77, 214, 201),       -- lime-400
        Warning = Color3.fromRGB(251, 191, 36),       -- amber-400
        Error = Color3.fromRGB(248, 113, 113),        -- red-400
        Electric = Color3.fromRGB(56, 189, 248),      -- sky-400
        Rainbow = Color3.fromRGB(244, 114, 182),      -- pink-400
        Frozen = Color3.fromRGB(103, 232, 249),       -- cyan-300
        Gold = Color3.fromRGB(250, 204, 21),          -- yellow-400
        ToggleOn = Color3.fromRGB(77, 214, 201),
        ToggleOff = Color3.fromRGB(30, 37, 45),
        ToggleKnob = Color3.fromRGB(10, 13, 16),
        SliderTrack = Color3.fromRGB(26, 31, 38),
        SliderFill = Color3.fromRGB(77, 214, 201),
    },
    
    -- Runtime data (populated during initialization)
    RuntimeData = {
        myPlayer = nil,
        playerHumanoid = nil,
        playerRootPart = nil,
        eggLocations = {},
        huntNPCs = {},
        lastTrustCheck = 0,
        trustScore = 0,
    },
    
    -- Utility references
    Services = setmetatable({}, {
        __index = function(t, k)
            return game:GetService(k)
        end
    })
}

-- Export to global context
_G._MiracleHubSteaLEgg = ctx
_G._MiracleHubSession = _G._MiracleHubSession or 0
_G._MiracleHubSession += 1

print("[MiracleHub] Steal An Egg Core Loaded | Session:", _G._MiracleHubSession)

    return ctx
end
