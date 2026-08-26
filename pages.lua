-- Steal An Egg - Miracle Hub Pages/UI Module
-- File: pages.lua
-- Builds the UI components for each tab
--
-- Loader contract (loader.lua): module must `return function(ctx)`.

return function(ctx)
local session = _G._MiracleHubSession

-- UI Builder Functions (injected by shared framework)
local CreateSectionCard = ctx.UI.CreateSectionCard
local CreateSubHeader = ctx.UI.CreateSubHeader
local CreateToggle = ctx.UI.CreateToggle
local CreateSlider = ctx.UI.CreateSlider
local CreateDropdown = ctx.UI.CreateDropdown
local CreateDynamicDropdown = ctx.UI.CreateDynamicDropdown
local CreateMultiSelect = ctx.UI.CreateMultiSelect
local CreateActionButton = ctx.UI.CreateActionButton
local CreateInfoText = ctx.UI.CreateInfoText
local CreateStatRow = ctx.UI.CreateStatRow

-- Color Palette
local Colors = {
    Success = Color3.fromRGB(0, 255, 127),
    Warning = Color3.fromRGB(255, 194, 68),
    Danger = Color3.fromRGB(255, 68, 68),
    Info = Color3.fromRGB(68, 138, 255),
    TextMuted = Color3.fromRGB(150, 150, 150),
    Accent = Color3.fromRGB(0, 212, 255),
    Background = Color3.fromRGB(30, 30, 35),
    Surface = Color3.fromRGB(45, 45, 50),
    Border = Color3.fromRGB(60, 60, 65)
}

-- ============================================================
-- HOME TAB
-- ============================================================

ctx.registerPage("Home", function()
    local card, content = CreateSectionCard("🏠 Welcome to Steal An Egg!", 1, Colors.Info)
    CreateSubHeader(content, "Quick Start")
    
    CreateInfoText(content, "💡 Getting Started", 
        "1. Toggle ENABLE to activate all features\n" ..
        "2. Use TRUST BUILD indicator to monitor anti-cheat safety\n" ..
        "3. Enable stealth mode for maximum undetectability\n\n" ..
        "**Note:** Wait for trust score to reach 80% before heavy automation",
        Colors.TextMuted
    )
    
    -- Trust Status Display
    if typeof(ctx.CheckTrustStatus) == "function" then
        local trustStatus = ctx.CheckTrustStatus()
        
        local statusColor = trustStatus.score >= 80 and Colors.Success or 
                           trustStatus.score >= 50 and Colors.Warning or Colors.Danger
        
        CreateStatRow(content, "Trust Score", string.format("%d%% (%s)", trustStatus.score, trustStatus.status:upper()), statusColor)
    else
        CreateStatRow(content, "Trust Score", "Loading...", Colors.Accent)
    end
    
    -- Session Info
    CreateStatRow(content, "Session", "Running", Colors.Success)
    CreateStatRow(content, "Auto-Farm", ctx.States.autoFarm and "ON ✅" or "OFF ❌", ctx.States.autoFarm and Colors.Success or Colors.TextMuted)
    CreateStatRow(content, "Smooth Travel", ctx.States.smoothTravel and "ON ✅" or "OFF ❌", ctx.States.smoothTravel and Colors.Success or Colors.TextMuted)
    CreateStatRow(content, "Stealth Mode", ctx.States.stealthMode and "ACTIVE 🔒" or "INACTIVE ⚠️", ctx.States.stealthMode and Colors.Success or Colors.Warning)
end)

-- ============================================================
-- AUTO FARM TAB
-- ============================================================

ctx.registerPage("Auto Farm", function()
    local card, content = CreateSectionCard("⛏️ Auto Farm Settings", 1, Colors.Success)
    CreateSubHeader(content, "Automation Controls")
    
    -- Main toggle
    CreateToggle(content, "ENABLE Auto Farm", "enabled", "Activate all farming systems", function(state)
        print("[StealAnEgg] Global enabled:", state)
        task.wait(0.5)
        
        if state and ctx.WaitForTrustBuild then
            -- Ensure trust is built before enabling other features
            ctx.WaitForTrustBuild()
        end
    end)
    
    CreateSubHeader(content, "Farm Actions")
    
    -- Auto collect eggs
    CreateToggle(content, "Auto Collect Eggs", "autoCollect", 
        "Automatically collect nearby eggs when trusted", function(state)
        print("[StealAnEgg] Auto collect:", state)
    end)
    
    -- Auto hunt NPCs
    CreateToggle(content, "Auto Hunt NPCs", "autoHunt", 
        "Automatically attack and farm nearby enemies", function(state)
        print("[StealAnEgg] Auto hunt:", state)
    end)
    
    -- Stealth mode
    CreateToggle(content, "🔒 Stealth Mode", "stealthMode", 
        "Maximize undetectability (slower but safer)", function(state)
        print("[StealAnEgg] Stealth mode:", state)
    end)
    
    CreateSubHeader(content, "Smart Features")
    
    -- Anti-AFK system
    CreateToggle(content, "Anti-AFK Movement", "antiAFK", 
        "Perform small movements to avoid AFK detection", function(state)
        if ctx.EnableAntiAFK then
            ctx.EnableAntiAFK(state)
        end
    end)
    
    -- Smooth travel
    CreateToggle(content, "Smooth Travel", "smoothTravel", 
        "Enable gentle movement (trust-safe flying)", function(state)
        if ctx.EnableSmoothTravel then
            ctx.EnableSmoothTravel(state)
        end
    end)
    
    -- Travel speed slider
    CreateSlider(content, "Movement Speed", 0.5, 10, "travelSpeed", "", function(value)
        print("[StealAnEgg] Travel speed set to:", value)
    end)
    
    CreateSubHeader(content, "Actions")
    
    -- Manual collection button
    CreateActionButton(content, "🥚 Force Egg Collection", function()
        if ctx.CollectEgg then
            local success = pcall(ctx.CollectEgg)
            if success then
                print("[StealAnEgg] ✓ Manual egg collection triggered")
            end
        end
    end, Colors.Success)
    
    -- Manual combat button
    CreateActionButton(content, "⚔️ Force Combat Attack", function()
        if ctx.HuntNPC then
            local success = pcall(ctx.HuntNPC)
            if success then
                print("[StealAnEgg] ✓ Manual combat attack triggered")
            end
        end
    end, Colors.Danger)
    
    -- Reset button
    CreateActionButton(content, "🔄 Reset & Rebuild Trust", function()
        ctx.States.enabled = false
        ctx.States.autoFarm = false
        ctx.States.smoothTravel = false
        ctx.States.antiAFK = false
        
        if not ctx.States.stealthMode then
            ctx.States.stealthMode = true
        end
        
        print("[StealAnEgg] ✓ Trust reset initiated - standing still to rebuild...")
    end, Colors.Warning)
    
    CreateInfoText(content, "ℹ Safety Tip", 
        "**Always stay in stealth mode** to avoid trust freeze.\n" ..
        "**Wait for trust score ≥80%** before intensive actions.\n" ..
        "**Avoid rapid movements** during initial game start.",
        Colors.Accent
    )
end)

-- ============================================================
-- EGG TRACKER TAB
-- ============================================================

ctx.registerPage("Egg Tracker", function()
    local card, content = CreateSectionCard("🥚 Egg Tracking", 1, Colors.Accent)
    CreateSubHeader(content, "Egg Collection Monitor")
    
    CreateInfoText(content, "📊 How It Works", 
        "**Auto Detection:** Automatically finds nearby eggs using proximity checks\n\n" ..
        "**Safe Collection:** Only collects when:\n" ..
        "- Trust score ≥ 80%\n" ..
        "- Within 15 stud range\n" ..
        "- In trust-building phase avoided\n\n" ..
        "**Remote Integration:** Uses legitimate egg collection remotes to appear natural",
        Colors.TextMuted
    )
    
    -- Dynamic dropdown for egg types (to be populated)
    CreateDynamicDropdown(content, "Filter by Type", getEggTypeOptions, "eggTypeFilter", function(selected)
        print("[StealAnEgg] Filter changed to:", selected)
    end)
    
    CreateSubHeader(content, "Rarity Priority")
    
    -- Multi-select for rarity preferences
    CreateMultiSelect(content, "Priority Rarities", ctx.Data.GEAR_DATA.RARITIES, "rarityPriorities", function(selected)
        print("[StealAnEgg] Rarity priorities:", table.concat(selected, ", "))
    end)
    
    CreateInfoText(content, "🎯 Auto-Collection Behavior", 
        "**Sequential Targeting:** Prioritizes closest first\n" ..
        "**Cooldown Protection:** Waits 0.5s between collections\n" ..
        "**Stealth Approach:** Moves slowly toward target before collecting",
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
        "**IMPORTANT:** The trust system monitors:\n" ..
        "- WalkSpeed variations\n" ..
        "- Jump height patterns\n" ..
        "- Teleport/clip detection\n" ..
        "- Velocity anomalies",
        Colors.TextMuted
    )
    
    CreateSubHeader(content, "Trust Building Optimization")
    
    -- Min trust build time
    CreateSlider(content, "Min Trust Build Time", 2, 20, "minTrustTime", "s", function(value)
        ctx.TRUST_SETTINGS.MIN_TRUST_BUILD_TIME = value
        print("[StealAnEgg] Trust build time:", value .. "s")
    end)
    
    -- Max walkspeed variation
    CreateSlider(content, "WalkSpeed Variation Limit", 0, 5, "walkspeedLimit", "%", function(value)
        ctx.TRUST_SETTINGS.MAX_WALK_SPEED_VARIATION = value / 100
        print("[StealAnEgg] Walkspeed limit:", value .. "%")
    end)
    
    -- Max jump height variation
    CreateSlider(content, "Jump Height Variation", 1, 3, "jumpHeightLimit", "x", function(value)
        ctx.TRUST_SETTINGS.MAX_JUMP_HEIGHT_VARIATION = value
        print("[StealAnEgg] Jump height multiplier:", value .. "x")
    end)
    
    CreateSubHeader(content, "Traversal Methods")
    
    -- Smooth travel configuration
    CreateToggle(content, "Use Smooth Travel", "smoothTravel", 
        "Gentle movement instead of instant teleport", function(state)
        if ctx.EnableSmoothTravel then
            ctx.EnableSmoothTravel(state)
        end
    end)
    
    CreateSlider(content, "Smooth Travel Speed", 1, 30, "smoothTravelSpeed", "stud/s", function(value)
        ctx.TRUST_SETTINGS.SMOOTH_TRAVEL_SPEED = value
        print("[StealAnEgg] Smooth travel speed:", value .. " stud/s")
    end)
    
    CreateInfoText(content, "🛡️ Movement Best Practices", 
        "**DO:**\n" ..
        "- Enable smooth travel for long-distance movement\n" ..
        "- Allow trust to build after respawn\n" ..
        "- Use anti-AFK to maintain movement history\n\n" ..
        "**DON'T:**\n" ..
        "- Rapidly change speeds\n" ..
        "- Instant teleport large distances\n" ..
        "- Disable gravity while moving",
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
    CreateToggle(content, "Verbose Logging", "debugLogging", "Show detailed action logs in chat", function(state)
        print("[StealAnEgg] Debug logging:", state)
    end)
    
    -- Trust monitoring interval
    CreateSlider(content, "Trust Check Interval", 1, 10, "trustCheckInterval", "s", function(value)
        print("[StealAnEgg] Trust check interval:", value .. "s")
    end)
    
    CreateSubHeader(content, "System Information")
    
    -- Session ID display
    CreateStatRow(content, "Session ID", tostring(_G._MiracleHubSession), Colors.Accent)
    CreateStatRow(content, "Mobile Mode", tostring(_G._MiracleHubIsMobile or false), Colors.TextMuted)
    CreateStatRow(content, "Game Name", ctx.GAME_NAME, Colors.Info)
    
    -- Version info
    CreateInfoText(content, "📋 System Status", 
        "**All systems operational**\n" ..
        "**Anti-cheat evasion**: ACTIVE\n" ..
        "**Trust building**: READY",
        Colors.Success
    )
    
    CreateSubHeader(content, "Safety & Cleanup")
    
    -- Emergency disable
    CreateActionButton(content, "🚨 EMERGENCY DISABLE", function()
        ctx.States.enabled = false
        ctx.States.autoFarm = false
        ctx.States.smoothTravel = false
        ctx.States.antiAFK = false
        
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

-- ============================================================
-- HELPER FUNCTIONS FOR DYNAMIC DROPDOWNS
-- ============================================================

local function getEggTypeOptions()
    local options = {}
    
    -- Get egg models from workspace
    local eggs = {}
    for _, instance in ipairs(workspace:GetDescendants()) do
        if instance:IsA("Model") and instance.Name:lower():find("egg") and instance.Parent == workspace then
            table.insert(eggs, instance)
        end
    end
    
    local seenNames = {}
    
    for _, egg in ipairs(eggs) do
        local name = egg.Name
        if not seenNames[name] then
            table.insert(options, name)
            seenNames[name] = true
        end
    end
    
    -- Add common types
    local commonTypes = {"Normal Egg", "Dragon Egg", "Demonic Egg"}
    for _, t in ipairs(commonTypes) do
        if not seenNames[t] then
            table.insert(options, t)
        end
    end
    
    return #options > 0 and options or {"No eggs detected"}
end

print("[MiracleHub] Steal An Egg Pages Module Loaded | Ready for UI registration")
end
