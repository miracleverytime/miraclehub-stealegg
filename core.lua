-- Steal An Egg - Miracle Hub Core Configuration
-- File: core.lua
--
-- Loader contract (loader.lua):
--   loadstring(src)()        -> returns a function
--   pcall(moduleFn, ctx)     -> invokes module with shared ctx
--   return value is ignored.
-- Therefore this module MUST populate the passed-in `ctx` table
-- (NOT a local one) so downstream modules (ui.lua, logic.lua, ...)
-- can read ctx.Colors, ctx.playerGui, ctx.Services, etc.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

return function(ctx)
    ctx._SessionStartTime = ctx._SessionStartTime or tick()

    -- ── Identity / metadata ───────────────────────────────────────────
    ctx.GAME_NAME = "Steal An Egg"
    ctx.PLACE_ID  = 107778070777162
    ctx.ACTIVE_LOOP_KEYS   = {}
    ctx.ACTIVE_LOOP_LABELS = {}

    -- ── UI Configuration (consumed by bootstrap.lua / pages.lua) ──────
    ctx.PAGES_CONFIG = {
        {name = "Home",       key = "home",      icon = "🏠"},
        {name = "Auto Farm",  key = "autofarm",  icon = "⛏️"},
        {name = "Egg Tracker",key = "eggs",      icon = "🥚"},
        {name = "Movement",   key = "movement",  icon = "🚶"},
        {name = "Settings",   key = "settings",  icon = "⚙️"},
    }

    -- ── Remote/Network References ──────────────────────────────────────
    -- These are the literal remote names that appear under
    -- ReplicatedStorage.Network in the real game. The Network_m client
    -- library (loaded by logic.lua) wraps all of these in safe
    -- Fire/Invoke helpers, so this table is purely informational.
    ctx.Data = {
        PACKETS = {
            AdminAbuse_GetActiveEvents = "AdminAbuse_GetActiveEvents",
            AdminAbuse_GetEventNames   = "AdminAbuse_GetEventNames",
            ExperienceEventPrompt_MarkSeen = "Experience Event Prompt: Mark Seen",
            ExperienceEventPrompt_GetState = "Experience Event Prompt: Get State",
        },
        GUARDS = {
            GuardTutorial_RequestRuntimeState = "GuardTutorial: RequestRuntimeState",
            GuardTutorial_GetState            = "ServerLuck:GetState",
        },
        GEAR_DATA = {
            RARITIES = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical"},
            TYPES    = {"Normal", "Dragon", "Demonic", "Great Bloom", "Sakura"},
        },
        SAFE_ZONES = {
            SPAWN = true,
        },
    }

    -- ── Network Endpoints (resolved at runtime by logic.lua) ──────────
    -- These are the groupings of the real NETWORK_MAP exposed under
    -- ReplicatedStorage.Library.Globals.Constants.NETWORK_MAP.
    ctx.NETWORK_ENDPOINTS = {
        ADMIN_ABUSE       = "AdminAbuse",
        GUARD_TUTORIAL    = "GuardTutorial",
        EXPERIENCE_EVENTS = "ExperienceEventPrompt",
        BACKPACK          = "Backpack",
        OFFLINE_ASSETS    = "OfflineAssets",
        ACTIVE_ASSETS     = "ActiveAssets",
        EGGS              = "Eggs",
        PLOTS             = "Plots",
        GUARDS            = "Guards",
    }

    -- ── Movement trust settings (anti-cheat evasion) ─────────────────
    ctx.TRUST_SETTINGS = {
        ENABLE_SMOOTH_MOVEMENT     = true,
        MAX_WALK_SPEED_VARIATION   = 0.5,
        MAX_JUMP_HEIGHT_VARIATION  = 1.2,
        MIN_TRUST_BUILD_TIME       = 5,
        SMOOTH_TRAVEL_SPEED        = 16,
        ANTI_AFK_INTERVAL          = 25,
    }

    -- ── Mutable game-state flags (logic.lua flips these) ──────────────
    ctx.States = {
        enabled                 = false,
        autoFarm                = false,
        autoHunt                = false,
        autoCollect             = false,
        autoSteal               = false,
        stealPreferFirst        = true,
        stealTweenSpeed         = 300,
        stealDynamicSpeed       = true,
        stealAreaFilter         = "",
        smoothTravel            = false,
        antiAFK                 = false,
        stealthMode             = true,
        trustBuildingComplete   = false,
        showNotifications       = true,
    }

    -- ── Color Palette (required by ui.lua line 18-51) ─────────────────
    ctx.Colors = {
        Background          = Color3.fromRGB(10, 13, 16),
        BackgroundLight     = Color3.fromRGB(18, 22, 27),
        BackgroundLighter   = Color3.fromRGB(26, 31, 38),
        Surface             = Color3.fromRGB(32, 38, 46),
        SurfaceLight        = Color3.fromRGB(40, 48, 58),
        Border              = Color3.fromRGB(30, 37, 45),
        BorderLight         = Color3.fromRGB(40, 100, 95),
        TextPrimary         = Color3.fromRGB(209, 213, 219),
        TextSecondary       = Color3.fromRGB(148, 155, 165),
        TextMuted           = Color3.fromRGB(113, 113, 122),
        Accent              = Color3.fromRGB(77, 214, 201),
        Success             = Color3.fromRGB(77, 214, 201),
        Warning             = Color3.fromRGB(251, 191, 36),
        Error               = Color3.fromRGB(248, 113, 113),
        Electric            = Color3.fromRGB(56, 189, 248),
        Rainbow             = Color3.fromRGB(244, 114, 182),
        Frozen              = Color3.fromRGB(103, 232, 249),
        Gold                = Color3.fromRGB(250, 204, 21),
        ToggleOn            = Color3.fromRGB(77, 214, 201),
        ToggleOff           = Color3.fromRGB(30, 37, 45),
        ToggleKnob          = Color3.fromRGB(10, 13, 16),
        SliderTrack         = Color3.fromRGB(26, 31, 38),
        SliderFill          = Color3.fromRGB(77, 214, 201),
    }

    -- ── Runtime data (populated as game state is observed) ────────────
    ctx.RuntimeData = {
        myPlayer        = localPlayer,
        playerHumanoid  = nil,
        playerRootPart  = nil,
        eggLocations    = {},
        huntNPCs        = {},
        lastTrustCheck  = 0,
        trustScore      = 0,
        lastStealUid    = nil,
        lastHuntUid     = nil,
        stealStolen     = 0,
        stealFailed     = 0,
    }

    -- ── Service refs (live, resolved on-demand via metatable) ─────────
    ctx.Services = setmetatable({}, {
        __index = function(_, k)
            return game:GetService(k)
        end,
    })

    -- ── Service handles that ui.lua reads at line 22-24 ───────────────
    ctx.playerGui        = playerGui
    ctx.player           = localPlayer
    ctx.TweenService     = TweenService
    ctx.UserInputService = UserInputService
    ctx.RunService       = RunService
    ctx.Players          = Players

    -- ── Session marker (read by bootstrap.lua line 1338/469/948) ──────
    _G._MiracleHubSession = (_G._MiracleHubSession or 0) + 1
    ctx.SESSION           = _G._MiracleHubSession

    -- ── SESSION GUARD: hapus GUI inject sebelumnya saat re-inject ─────
    -- Mencegah menu ganda (duplicate) karena ScreenGui lama tidak di-destroy
    -- oleh framework. Nama GUI = "MiracleHub" (lihat ui.lua/ui.mobile.lua).
    -- Juga reset GameCleanup lama agar tidak menumpuk double-loop.
    pcall(function()
        local old = playerGui:FindFirstChild("MiracleHub")
        if old then old:Destroy() end
        local oldAlt = playerGui:FindFirstChild("MiracleHubSteaLEgg")
        if oldAlt then oldAlt:Destroy() end
        -- Framework shared menandai ScreenGui-nya dengan attribute "BuildTag"
        -- (ui.mobile.lua / ui.lua). Hancurkan semua ScreenGui hub lama agar
        -- re-inject tidak menyisakan menu ganda.
        for _, sg in ipairs(playerGui:GetChildren()) do
            if sg:IsA("ScreenGui") and sg:GetAttribute("BuildTag") then
                sg:Destroy()
            end
        end
    end)
    pcall(function()
        if _G.GameCleanup then
            for _, cleanup in ipairs(_G.GameCleanup) do
                pcall(cleanup)
            end
        end
        _G.GameCleanup = {}
    end)

    -- ── Global mirror (read by logic.lua) ─────────────────────────────
    _G._MiracleHubSteaLEgg = ctx

    print("[MiracleHub] Steal An Egg Core Loaded | Session:", _G._MiracleHubSession)
end
