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
