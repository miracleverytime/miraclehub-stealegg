-- Steal An Egg - Miracle Hub Pages/UI Module
-- File: pages.lua
-- Builds the UI components for each tab and wires them to real game
-- actions through ctx.* helpers exposed by logic.lua.
--
-- Loader contract (loader.lua): module must `return function(ctx)`.

return function(ctx)
local session = _G._MiracleHubSession

-- UI Builder Functions (injected by shared framework)
local CreateSectionCard    = ctx.UI.CreateSectionCard
local CreateSubHeader     = ctx.UI.CreateSubHeader
local CreateToggle        = ctx.UI.CreateToggle
local CreateSlider        = ctx.UI.CreateSlider
local CreateDropdown      = ctx.UI.CreateDropdown
local CreateDynamicDropdown = ctx.UI.CreateDynamicDropdown
local CreateMultiSelect   = ctx.UI.CreateMultiSelect
local CreateActionButton  = ctx.UI.CreateActionButton
local CreateInfoText      = ctx.UI.CreateInfoText
local CreateStatRow       = ctx.UI.CreateStatRow

-- Color Palette (UI-local override of ctx.Colors)
local Colors = {
    Success   = ctx.Colors.Success,
    Warning   = ctx.Colors.Warning,
    Danger    = ctx.Colors.Error,
    Info      = ctx.Colors.Electric,
    TextMuted = ctx.Colors.TextMuted,
    Accent    = ctx.Colors.Accent,
    Background= ctx.Colors.Background,
    Surface   = ctx.Colors.Surface,
    Border    = ctx.Colors.Border,
}

-- ============================================================
-- HELPERS
-- ============================================================

local function getEggCategoryOptions()
    local options = {}
    local seen = {}

    -- Pull the live snapshot of area eggs.
    local records = {}
    if ctx.GetAreaEggs then
        local ok, snap = pcall(ctx.GetAreaEggs)
        if ok and type(snap) == "table" then records = snap end
    end

    for _, rec in ipairs(records) do
        if rec.AssetCategory and not seen[rec.AssetCategory] then
            seen[rec.AssetCategory] = true
            table.insert(options, rec.AssetCategory)
        end
        if rec.AreaId and not seen[rec.AreaId] then
            seen[rec.AreaId] = true
            table.insert(options, rec.AreaId)
        end
    end

    -- Always offer common type placeholders so the dropdown isn't empty.
    for _, typeName in ipairs(ctx.Data.GEAR_DATA.TYPES) do
        if not seen[typeName] then
            seen[typeName] = true
            table.insert(options, typeName)
        end
    end

    if #options == 0 then
        return {"No eggs detected"}
    end
    return options
end

-- ============================================================
-- HOME TAB
-- ============================================================

ctx.registerPage("Home", function()
    local card, content = CreateSectionCard("🏠 Welcome to Steal An Egg!", 1, Colors.Info)
    CreateSubHeader(content, "Quick Start")

    CreateInfoText(content, "💡 Getting Started",
        "1. Toggle ENABLE to activate all features\n" ..
        "2. Auto-Farm grabs the closest dropped area egg (fitur utama)\n" ..
        "3. Auto-Hunt = DNA steal (mati jika flag dev off; farm tetap jalan)\n\n" ..
        "**Note:** Stay outside the safe zone or the game will block your requests.",
        Colors.TextMuted
    )

    -- Trust Status Display
    if typeof(ctx.CheckTrustStatus) == "function" then
        local trustStatus = ctx.CheckTrustStatus()

        local statusColor = trustStatus.score >= 80 and Colors.Success or
                           trustStatus.score >= 50 and Colors.Warning or Colors.Danger

        CreateStatRow(content, "Trust Score", string.format("%d%% (%s)", trustStatus.score, (trustStatus.status or "unknown"):upper()), statusColor)
    else
        CreateStatRow(content, "Trust Score", "Loading...", Colors.Accent)
    end

    -- Session Info
    CreateStatRow(content, "Session", "Running", Colors.Success)
    CreateStatRow(content, "Auto Steal Egg", ctx.States.autoSteal and "ON ✅" or "OFF ❌", ctx.States.autoSteal and Colors.Success or Colors.TextMuted)
    CreateStatRow(content, "Smooth Travel", ctx.States.smoothTravel and "ON ✅" or "OFF ❌", ctx.States.smoothTravel and Colors.Success or Colors.TextMuted)
    CreateStatRow(content, "Stealth Mode", ctx.States.stealthMode and "ACTIVE 🔒" or "INACTIVE ⚠️", ctx.States.stealthMode and Colors.Success or Colors.Warning)
end)

-- ============================================================
-- AUTO FARM TAB
-- ============================================================

ctx.registerPage("Auto Farm", function()
    local card, content = CreateSectionCard("⛏️ Auto Farm & Steal", 1, Colors.Success)
    CreateSubHeader(content, "Auto Steal Egg Controls")

    -- Main Steal enable
    CreateToggle(content, "🥚 Auto Steal Egg (Loop)", "autoSteal",
        "Tween otomatis ke egg -> ambil (CarryFieldEgg) -> bawa ke base & claim", function(state)
            if ctx.SetAutoSteal then
                ctx.SetAutoSteal(state)
            else
                ctx.States.autoSteal = state and true or false
            end
            print("[StealAnEgg] Auto steal:", state)
        end
    )

    -- Prefer FirstAreaEgg
    CreateToggle(content, "Utamakan FirstAreaEgg", "stealPreferFirst",
        "Prioritaskan egg FirstAreaEgg_ (dekat base, mudah dicuri)", function(state)
            ctx.States.stealPreferFirst = state and true or false
            print("[StealAnEgg] Prefer FirstAreaEgg:", state)
        end
    )

    -- Area filter
    CreateDropdown(content, "Filter Area", {"", "Forest", "Lake", "Desert", "Snow", "Volcano", "Prehistoric", "Jungle", "Cosmic", "Abyss Ocean", "Titan Temple", "Cherry Blossom"}, "stealAreaFilter", function(value)
        ctx.States.stealAreaFilter = value
        print("[StealAnEgg] Steal area filter:", value)
    end)

    -- Dynamic speed toggle
    CreateToggle(content, "⚡ Max Speed (300 studs/s)", "stealDynamicSpeed",
        "Gunakan kecepatan lari maksimal game (300 studs/s hardcap)", function(state)
            ctx.States.stealDynamicSpeed = state and true or false
            print("[StealAnEgg] Max Speed 300 studs/s:", ctx.States.stealDynamicSpeed)
        end
    )

    -- Tween speed
    CreateSlider(content, "Speed Limit (studs/s)", 50, 300, "stealTweenSpeed", "studs/s", function(value)
        ctx.States.stealTweenSpeed = value
        print("[StealAnEgg] Steal speed cap:", value)
    end)

    -- Stats
    CreateStatRow(content, "Stolen (session)", tostring(ctx.RuntimeData.stealStolen or 0), Colors.Success)
    CreateStatRow(content, "Failed (session)", tostring(ctx.RuntimeData.stealFailed or 0), Colors.Warning)

    CreateInfoText(content, "ℹ Auto Steal Egg",
        "**MoveTo (physics asli)** - berjalan via jalur Roblox, TIDAK menembus tembok (anti mati mendadak).\n" ..
        "**Alur:** cari egg terdekat -> jalan (MoveTo) -> CarryFieldEgg -> bawa ke **safe zone** (belakang garis pemisah) -> server auto-claim.\n" ..
        "**Anti-drop:** jika egg jatuh kena penjaga saat dibawa, langsung diambil ulang (tanpa ke base dulu).\n" ..
        "**Max Account Speed:** Memakai kecepatan lari penuh karaktermu dari treadmill/upgrade tanpa dibatasi.",
        Colors.Info
    )

    -- Stealth mode
    CreateToggle(content, "🔒 Stealth Mode", "stealthMode",
        "Throttles travel speed for safer movement", function(state)
            if ctx.SetStealth then
                ctx.SetStealth(state)
            else
                ctx.States.stealthMode = state and true or false
            end
            print("[StealAnEgg] Stealth mode:", state)
        end
    )

    CreateSubHeader(content, "Convenience")

    -- Anti-AFK system
    CreateToggle(content, "Anti-AFK Movement", "antiAFK",
        "Subtle motion pulses every " .. tostring(ctx.TRUST_SETTINGS.ANTI_AFK_INTERVAL) .. "s to avoid idle kicks", function(state)
            ctx.States.antiAFK = state and true or false
            if ctx.EnableAntiAFK then
                ctx.EnableAntiAFK(state)
            end
        end
    )

    -- Smooth travel
    CreateToggle(content, "Smooth Travel", "smoothTravel",
        "CFrame-tween movement instead of instant teleport", function(state)
            ctx.States.smoothTravel = state and true or false
            if ctx.EnableSmoothTravel then
                ctx.EnableSmoothTravel(state)
            end
        end
    )

    -- Travel speed slider (studs/s)
    CreateSlider(content, "Travel Speed", 4, 30, "travelSpeed", "studs/s", function(value)
        if ctx.TRUST_SETTINGS then
            ctx.TRUST_SETTINGS.SMOOTH_TRAVEL_SPEED = value
        end
        print("[StealAnEgg] Travel speed set to:", value)
    end)

    CreateSubHeader(content, "Actions")

    -- Hatch all ready eggs
    CreateActionButton(content, "🐣 Hatch Ready Eggs", function()
        if ctx.HatchReadyEggs then
            local n = ctx.HatchReadyEggs()
            print("[StealAnEgg] Hatched", n, "eggs")
        end
    end, Colors.Accent)

    -- Skip growth for all
    CreateActionButton(content, "⏩ Skip Growth (All)", function()
        if ctx.SkipGrowthForAll then
            local n = ctx.SkipGrowthForAll()
            print("[StealAnEgg] Skipped growth on", n, "eggs")
        end
    end, Colors.Warning)

    -- Upgrade base
    CreateActionButton(content, "🏗️ Upgrade Base", function()
        if ctx.UpgradeBase then
            local ok = ctx.UpgradeBase()
            print("[StealAnEgg] Base upgrade:", ok and "requested" or "rejected")
        end
    end, Colors.Info)

    -- Teleport home
    CreateActionButton(content, "🏠 Teleport to Base", function()
        if ctx.TeleportToBase then
            local ok, err = ctx.TeleportToBase()
            if not ok then
                warn("[StealAnEgg] Teleport failed:", tostring(err))
            end
        end
    end, Colors.Info)

    -- Reset button
    CreateActionButton(content, "🔄 Reset Automation", function()
        ctx.States.enabled    = false
        ctx.States.autoSteal  = false
        ctx.States.smoothTravel = false
        ctx.States.antiAFK    = false
        if ctx.SetAutoSteal then ctx.SetAutoSteal(false) end
        if ctx.EnableSmoothTravel then ctx.EnableSmoothTravel(false) end
        if ctx.EnableAntiAFK then ctx.EnableAntiAFK(false) end
        print("[StealAnEgg] State reset")
    end, Colors.Danger)

    CreateInfoText(content, "ℹ Safety Tip",
        "**Stay out of the safe zone** or ToolGameplayGuard will block your requests.\n" ..
        "**Wait for trust score ≥80%** before intensive actions.\n" ..
        "**Smooth travel** uses CFrame tweens, not WalkSpeed - avoids speed-flag triggers.",
        Colors.Accent
    )
end)

-- ============================================================
-- EGG TRACKER TAB
-- ============================================================

ctx.registerPage("Egg Tracker", function()
    local card, content = CreateSectionCard("🥚 Egg Tracking", 1, Colors.Accent)
    CreateSubHeader(content, "Area Egg Monitor")

    CreateInfoText(content, "📊 How It Works",
        "**Auto Detection:** Reads EggCmds.GetAreaEggSnapshot() and walks every record.\n\n" ..
        "**Safe Steal:** Only carries eggs that are in `Dropped` state.\n" ..
        "**Server-side validation:** The game checks distance + ownership server-side.\n" ..
        "**Range filter:** 350 studs around your character is the practical upper bound.\n\n" ..
        "**Note:** There is no `collectEgg` remote - the only legal API is `RequestCarryAreaEgg(Uid)`.",
        Colors.TextMuted
    )

    -- Dynamic dropdown for egg types (populated live from area records)
    CreateDynamicDropdown(content, "Filter by AssetCategory", getEggCategoryOptions, "eggTypeFilter", function(selected)
        print("[StealAnEgg] Filter changed to:", selected)
    end)

    CreateSubHeader(content, "Rarity Priority")

    -- Multi-select for category preferences
    CreateMultiSelect(content, "Priority Categories", ctx.Data.GEAR_DATA.TYPES, "rarityPriorities", function(selected)
        print("[StealAnEgg] Priority categories:", table.concat(selected, ", "))
    end)

    CreateInfoText(content, "🎯 Auto-Collection Behavior",
        "**Sequential Targeting:** Picks the closest dropped egg.\n" ..
        "**Cooldown Protection:** Waits 0.7s between attempts.\n" ..
        "**Safe-Zone Aware:** Pauses while in tagged safe zones.",
        Colors.Success
    )
end)

-- ============================================================
-- MOVEMENT TAB
-- ============================================================

ctx.registerPage("Movement", function()
    local card, content = CreateSectionCard("🚶 Movement Systems", 1, Colors.Warning)
    CreateSubHeader(content, "Anti-Cheat Movement Configuration")

    CreateInfoText(content, "⚠ Trust-Based Movement",
        "This section controls **movement validation bypass** systems designed to work with the game's trust scoring mechanism.\n\n" ..
        "**Watched signals:**\n" ..
        "- WalkSpeed changes (mitigated by CFrame tweens, not WalkSpeed writes)\n" ..
        "- Teleport/clip detection (mitigated by chunked tween steps)\n" ..
        "- Idle kick timer (mitigated by Anti-AFK pulses)\n" ..
        "- Tool use inside safe zones (mitigated by ToolGameplayGuard.CanActivateLocal)",
        Colors.TextMuted
    )

    CreateSubHeader(content, "Trust Building")

    -- Min trust build time
    CreateSlider(content, "Trust Warmup", 2, 20, "minTrustTime", "s", function(value)
        ctx.TRUST_SETTINGS.MIN_TRUST_BUILD_TIME = value
        print("[StealAnEgg] Trust build time:", value .. "s")
    end)

    -- Max walkspeed variation (kept for visual parity; we do not write WalkSpeed)
    CreateSlider(content, "WalkSpeed Variation Limit", 0, 5, "walkspeedLimit", "%", function(value)
        ctx.TRUST_SETTINGS.MAX_WALK_SPEED_VARIATION = value / 100
        print("[StealAnEgg] Walkspeed limit:", value .. "%")
    end)

    -- Max jump height variation
    CreateSlider(content, "Jump Height Variation", 1, 3, "jumpHeightLimit", "x", function(value)
        ctx.TRUST_SETTINGS.MAX_JUMP_HEIGHT_VARIATION = value
        print("[StealAnEgg] Jump height multiplier:", value .. "x")
    end)

    CreateSubHeader(content, "Traversal")

    -- Smooth travel configuration
    CreateToggle(content, "Use Smooth Travel", "smoothTravel",
        "Chunked CFrame tween instead of instant teleport", function(state)
            ctx.States.smoothTravel = state and true or false
            if ctx.EnableSmoothTravel then
                ctx.EnableSmoothTravel(state)
            end
        end
    )

    CreateSlider(content, "Smooth Travel Speed", 4, 30, "smoothTravelSpeed", "studs/s", function(value)
        ctx.TRUST_SETTINGS.SMOOTH_TRAVEL_SPEED = value
        print("[StealAnEgg] Smooth travel speed:", value .. " stud/s")
    end)

    CreateInfoText(content, "🛡️ Movement Best Practices",
        "**DO:**\n" ..
        "- Use smooth travel for long-distance movement\n" ..
        "- Allow trust warmup after spawning\n" ..
        "- Keep Anti-AFK enabled to dodge idle kicks\n\n" ..
        "**DON'T:**\n" ..
        "- Rapidly change WalkSpeed (we don't touch it - CFrame only)\n" ..
        "- Use tools inside safe zones (the guard module blocks them)",
        Colors.Info
    )
end)

-- ============================================================
-- SETTINGS TAB
-- ============================================================

ctx.registerPage("Settings", function()
    local card, content = CreateSectionCard("⚙️ Advanced Settings", 1, Colors.Danger)
    CreateSubHeader(content, "General Configuration")

    -- Keybind settings
    CreateInfoText(content, "🔑 Global Keybinds",
        "**Enabled/Toggled:** [Insert]\n" ..
        "**Open Menu:** [Insert]\n" ..
        "**Trust Check:** [Insert]",
        Colors.TextMuted
    )

    CreateSubHeader(content, "Debug & Monitoring")

    -- Debug logging
    CreateToggle(content, "Verbose Logging", "debugLogging", "Show detailed action logs in console", function(state)
        ctx.States.debugLogging = state and true or false
        print("[StealAnEgg] Debug logging:", state)
    end)

    -- Trust monitoring interval
    CreateSlider(content, "Trust Check Interval", 1, 10, "trustCheckInterval", "s", function(value)
        ctx.TRUST_SETTINGS.TRUST_CHECK_INTERVAL = value
        print("[StealAnEgg] Trust check interval:", value .. "s")
    end)

    CreateSubHeader(content, "System Information")

    -- Session ID display
    CreateStatRow(content, "Session ID", tostring(_G._MiracleHubSession), Colors.Accent)
    CreateStatRow(content, "Mobile Mode", tostring(_G._MiracleHubIsMobile or false), Colors.TextMuted)
    CreateStatRow(content, "Game Name", ctx.GAME_NAME, Colors.Info)
    CreateStatRow(content, "Place ID", tostring(ctx.PLACE_ID), Colors.TextMuted)

    -- Module availability (real signal that the wiring is right)
    local libStatus = {}
    for _, name in ipairs({"Network", "EggCmds", "AssetCmds", "BaseUpgradeClient", "Save", "ToolGameplayGuard", "PlotCmds"}) do
        local ok = pcall(function()
            return require(game:GetService("ReplicatedStorage").Library.Client[name])
        end)
        table.insert(libStatus, name .. (ok and " ✓" or " ✗"))
    end
    CreateStatRow(content, "Libraries", table.concat(libStatus, ", "),
        Colors.Success)

    -- Version info
    CreateInfoText(content, "📋 System Status",
        "**All systems operational**\n" ..
        "**Anti-cheat evasion**: CFrame-tween based (safer than WalkSpeed)\n" ..
        "**Trust building**: ready (uses warmup + safe-zone detection)",
        Colors.Success
    )

    CreateSubHeader(content, "Safety & Cleanup")

    -- Emergency disable
    CreateActionButton(content, "🚨 EMERGENCY DISABLE", function()
        ctx.States.enabled    = false
        ctx.States.autoSteal  = false
        ctx.States.smoothTravel = false
        ctx.States.antiAFK    = false
        if ctx.SetAutoSteal   then ctx.SetAutoSteal(false)   end
        if ctx.EnableSmoothTravel then ctx.EnableSmoothTravel(false) end
        if ctx.EnableAntiAFK  then ctx.EnableAntiAFK(false)  end
        print("[StealAnEgg] 🚨 EMERGENCY DISABLE - All systems halted")
    end, Colors.Danger)

    -- Full cleanup
    CreateActionButton(content, "🧹 Complete Cleanup", function()
        if _G.GameCleanup then
            for _, cleanup in ipairs(_G.GameCleanup) do
                pcall(cleanup)
            end
        end
        print("[StealAnEgg] ✅ Full cleanup executed")
    end, Colors.Danger)
end)

print("[MiracleHub] Steal An Egg Pages Module Loaded | Ready for UI registration")
end
