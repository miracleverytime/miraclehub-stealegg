-- Steal An Egg - Miracle Hub Logic Module
-- File: logic.lua
-- Implements automation, anti-cheat evasion, and remote management
--
-- Loader contract (loader.lua): module must `return function(ctx)`.
-- All public functions are written to `ctx` so pages.lua can call them
-- (ctx.EnableSmoothTravel, ctx.CollectEgg, ctx.HuntNPC, ...).

return function(ctx)
local session  = _G._MiracleHubSession
local isMobile = _G._MiracleHubIsMobile or false

-- ============================================================
-- UTILITY & HELPER FUNCTIONS
-- ============================================================

local function safeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        warn("[StealAnEgg]", tostring(result))
    end
    return success, result
end

local function GetRemote(path)
    local parts = string.split(path, ":")
    local instance = game:GetService(parts[1])
    
    for i = 2, #parts do
        if parts[i]:match("^%.") then
            -- Named argument syntax like "GuardTutorial: RequestRuntimeState"
            local arg = parts[i]:gsub(":", ""):match("%s*(.-)%s*$"):gsub("^%s*(.-)%s*$", "%1")
            break
        else
            instance = instance:FindFirstChild(parts[i])
            if not instance then return nil end
        end
    end
    
    return instance
end

local function FindRemoteByName(namePattern)
    local matches = {}
    local foundCount = 0
    
    local function search(root)
        if foundCount >= 50 then return end
        
        for _, child in ipairs(root:GetDescendants()) do
            if child:IsA("RemoteFunction") or child:IsA("RemoteEvent") then
                if child.Name:lower():find(namePattern:lower()) then
                    table.insert(matches, child)
                    foundCount += 1
                    if foundCount >= 50 then return end
                end
            end
        end
    end
    
    search(game.ReplicatedStorage)
    search(game.StarterPlayer)
    
    return matches
end

local function CleanUpString(str)
    if not str then return "" end
    return string.gsub(str, "%s+", "")
end

-- ============================================================
-- TRUST SYSTEM DETECTION & BUILDING
-- ============================================================

local function CheckTrustStatus()
    -- This attempts to detect current trust state from frame digest
    -- Since we can't directly access internal modules, we'll use behavioral checks
    
    local startTick = tick()
    local testJumpHeight = 0
    
    -- Jump and measure height (trust-safe test)
    local player = ctx.Services.Players.LocalPlayer
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then
        return {status = "unknown", score = 0}
    end
    
    -- Simple behavior check: can we jump normally?
    local originalPosition = rootPart.Position.Y
    humanoid.Jump = true
    
    task.wait(0.15)
    local currentY = rootPart.Position.Y
    testJumpHeight = math.max(currentY - originalPosition, 0)
    
    local jumpTime = tick() - startTick
    
    -- If we can jump at normal height (>2) within reasonable time (<0.3s), trust likely building
    local trustSafe = testJumpHeight > 2 and jumpTime < 0.5
    
    ctx.RuntimeData.trustScore = trustSafe and 100 or 0
    return {status = trustSafe and "trusted" or "untrusted", score = ctx.RuntimeData.trustScore, data = {jumpHeight = testJumpHeight}}
end

local function WaitForTrustBuild()
    local maxWait = ctx.TRUST_SETTINGS.MIN_TRUST_BUILD_TIME
    local startTime = tick()
    local lastCheck = startTime
    
    print("[StealAnEgg] Building movement trust... Please wait...")
    
    while tick() - startTime < maxWait do
        local status = CheckTrustStatus()
        
        -- If trust is high enough, we can proceed
        if status.score >= 80 then
            print("[StealAnEgg] ✓ Trust level achieved:", status.score .. "%")
            return true
        end
        
        -- Perform trust-building movement
        if ctx.TRUST_SETTINGS.ENABLE_SMOOTH_MOVEMENT then
            safePerformTrustBuildingMovement()
        end
        
        task.wait(1)
    end
    
    print("[StealAnEgg] ℹ Trust build period ended (max wait reached)")
    return true -- Continue anyway, trust may have built naturally
end

local function safePerformTrustBuildingMovement()
    local player = ctx.Services.Players.LocalPlayer
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then return end
    
    -- Small random movement to help trust build
    local angle = math.random() * math.pi * 2
    local distance = 2 + math.random() * 3
    
    local targetPos = rootPart.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
    
    -- Smooth interpolate over 0.5 seconds
    local totalTime = 0.5
    local steps = 10
    local dt = totalTime / steps
    
    for i = 1, steps do
        local progress = i / steps
        local newX = Lerp(rootPart.Position.X, targetPos.X, progress)
        local newZ = Lerp(rootPart.Position.Z, targetPos.Z, progress)
        rootPart.CFrame = CFrame.new(newX, rootPart.Position.Y, newZ)
        task.wait(dt)
    end
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

-- ============================================================
-- MOVEMENT SYSTEMS (Anti-Cheat Safe)
-- ============================================================

local function EnableSmoothTravel(enabled)
    if enabled and not ctx.States.smoothTravel then
        ctx.States.smoothTravel = true
        print("[StealAnEgg] ✅ Smooth Travel ENABLED (stealth mode)")
    elseif not enabled and ctx.States.smoothTravel then
        ctx.States.smoothTravel = false
        print("[StealAnEgg] ❌ Smooth Travel DISABLED")
    end
end

task.spawn(function()
    while _G._MiracleHubSession == session do
        if ctx.States.smoothTravel then
            local player = ctx.Services.Players.LocalPlayer
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local rootPart = character and character:FindFirstChild("HumanoidRootPart")
            
            if humanoid and rootPart then
                -- Apply subtle speed reduction to avoid triggering walkspeed anomaly
                local originalSpeed = humanoid.WalkSpeed
                
                -- Use trust-based speed modulation
                local trustFactor = ctx.RuntimeData.trustScore >= 80 and 1 or 0.3
                local effectiveSpeed = Lerp(originalSpeed, ctx.TRUST_SETTINGS.SMOOTH_TRAVEL_SPEED, trustFactor)
                
                if ctx.States.stealthMode then
                    -- In stealth mode, keep speeds very smooth
                    humanoid.WalkSpeed = Lerp(humanoid.WalkSpeed, effectiveSpeed, 0.1)
                else
                    -- Normal mode (less risky, might trigger if too fast)
                    humanoid.WalkSpeed = effectiveSpeed
                end
            end
        end
        
        task.wait(0.1)
    end
end)

local function EnableAntiAFK(enabled)
    if enabled then
        print("[StealAnEgg] ✅ Anti-AFK ENABLED")
    else
        print("[StealAnEgg] ❌ Anti-AFK DISABLED")
    end
end

task.spawn(function()
    while _G._MiracleHubSession == session do
        if ctx.States.antiAFK then
            local player = ctx.Services.Players.LocalPlayer
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            
            if humanoid and rootPart then
                -- Random small movement every interval
                if tick() % ctx.TRUST_SETTINGS.ANTI_AFK_INTERVAL < 1 then
                    local offsetX = (math.random() - 0.5) * 5
                    local offsetZ = (math.random() - 0.5) * 5
                    rootPart.CFrame = CFrame.new(rootPart.Position.X + offsetX, rootPart.Position.Y, rootPart.Position.Z + offsetZ)
                end
            end
        end
        task.wait(1)
    end
end)

-- ============================================================
-- FLY SYSTEM (Stealth Version)
-- ============================================================

task.spawn(function()
    while _G._MiracleHubSession == session do
        if ctx.States.enabled and ctx.States.autoFarm and ctx.TriggerFly and ctx.TriggerFly() then
            if ctx.States.stealthMode then
                -- Stealth fly: move with camera direction but don't fully disable gravity
                local player = ctx.Services.Players.LocalPlayer
                local character = player.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                local camera = workspace.CurrentCamera
                
                if humanoid and rootPart and camera then
                    -- Keep some velocity to appear "natural"
                    if not humanoid.FloorMaterial == Enum.Material.Air then
                        -- While airborne, apply subtle horizontal movement
                        local camDir = camera.CFrame.LookVector
                        local camRight = camera.CFrame.RightVector
                        
                        local moveAmount = 8 * ctx.TRUST_SETTINGS.SMOOTH_TRAVEL_SPEED
                        local intendedVelocity = (camDir + camRight * (math.random() - 0.5)) * moveAmount
                        
                        -- Apply force gradually over multiple frames
                        local currentVel = rootPart.AssemblyLinearVelocity
                        rootPart.AssemblyLinearVelocity = LerpVec3(currentVel, intendedVelocity, 0.1)
                    end
                    
                    -- Always enable CanCollide for collision detection (appears natural)
                    rootPart.CanCollide = true
                    task.wait(0.1)
                end
            end
        end
        task.wait(0.05)
    end
end)

function LerpVec3(v1, v2, t)
    return Vector3.new(
        Lerp(v1.X, v2.X, t),
        Lerp(v1.Y, v2.Y, t),
        Lerp(v1.Z, v2.Z, t)
    )
end

-- ============================================================
-- REMOTE HANDLING
-- ============================================================

local FireRemoteAsync = function(remoteNameOrPath, ...)
    local args = {...}  -- pack varargs into table
    local remote = GetRemote(remoteNameOrPath) or FindRemoteByName(remoteNameOrPath)[1]
    
    if not remote then
        warn("[StealAnEgg] Remote not found:", remoteNameOrPath)
        return false, "NOT_FOUND"
    end
    
    local success, result = pcall(function()
        if remote:IsA("RemoteFunction") then
            return remote:InvokeServer(unpack(args))
        elseif remote:IsA("RemoteEvent") then
            remote:FireServer(unpack(args))
            return true
        end
    end)
    
    return success, result
end

-- ============================================================
-- GAMEPLAY AUTOMATION HELPERS
-- ============================================================

function CollectClosestEgg()
    local player = ctx.Services.Players.LocalPlayer
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then return false end
    
    -- Search Workspace for egg models
    local eggs = {}
    for _, instance in ipairs(workspace:GetDescendants()) do
        if instance:IsA("Model") and instance.Name:lower():find("egg") and instance.Parent == workspace then
            table.insert(eggs, instance)
        end
    end
    
    local closestEgg = nil
    local minDistance = 10 -- Collection range
    
    for _, egg in ipairs(eggs) do
        local eggPart = egg:FindFirstChildWhichIsA("BasePart")
        if eggPart then
            local dist = (eggPart.Position - rootPart.Position).Magnitude
            if dist < minDistance then
                minDistance = dist
                closestEgg = egg
            end
        end
    end
    
    if closestEgg and minDistance < 15 then
        -- Move toward egg first (trust-safe approach)
        local eggPart = closestEgg:FindFirstChildWhichIsA("BasePart")
        if eggPart then
            local direction = (eggPart.Position - rootPart.Position).Unit
            rootPart.CFrame = CFrame.new(rootPart.Position + direction * 5)
            task.wait(0.3)
            
            -- Now collect (assuming auto-collection or proximity trigger)
            task.wait(0.5)
            
            -- Try explicit collection if needed
            if FireRemoteAsync("collectEgg") or FireRemoteAsync("collect") then
                print("[StealAnEgg] ✅ Collected egg via remote")
            end
            
            return true
        end
    end
    
    return false
end

function AutoHuntNPC()
    local player = ctx.Services.Players.LocalPlayer
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then return false end
    
    -- Search for NPC enemies
    local npcs = {}
    for _, instance in ipairs(workspace:GetDescendants()) do
        if instance:IsA("Model") and (instance.Name:lower():find("npc") or instance.Name:lower():find("enemy")) and instance.Parent == workspace then
            table.insert(npcs, instance)
        end
    end
    
    local closestEnemy = nil
    local minDistance = 20 -- Attack range
    
    for _, npc in ipairs(npcs) do
        local enemyPart = npc:FindFirstChildWhichIsA("BasePart")
        if enemyPart then
            local dist = (enemyPart.Position - rootPart.Position).Magnitude
            if dist < minDistance then
                minDistance = dist
                closestEnemy = npc
            end
        end
    end
    
    if closestEnemy and minDistance < 30 then
        -- Move into attack range
        local enemyPart = closestEnemy:FindFirstChildWhichIsA("BasePart")
        if enemyPart then
            local direction = (enemyPart.Position - rootPart.Position).Unit
            rootPart.CFrame = CFrame.new(rootPart.Position + direction * 8)
            task.wait(0.5)
            
            -- Try attack action
            if FireRemoteAsync("attack") or FireRemoteAsync("combatAttack") then
                print("[StealAnEgg] ⚔️ Attempted combat attack")
                return true
            end
        end
    end
    
    return false
end

-- ============================================================
-- SESSION CLEANUP
-- ============================================================

local CleanupRoutine = function()
    print("[StealAnEgg] Cleaning up Steal An Egg module...")
    
    -- Disable all active systems
    ctx.States.enabled = false
    ctx.States.autoFarm = false
    ctx.States.smoothTravel = false
    ctx.States.antiAFK = false
    
    -- Clear runtime data
    ctx.RuntimeData = {}
    
    print("[StealAnEgg] ✅ Cleanup complete")
end

-- Hook into global cleanup
_G.GameCleanup = _G.GameCleanup or {}
table.insert(_G.GameCleanup, CleanupRoutine)

print("[MiracleHub] Steal An Egg Logic Module Initialized | Session:", session)

-- Export public API to ctx (consumed by pages.lua)
ctx.FireRemote          = FireRemoteAsync
ctx.EnableSmoothTravel  = EnableSmoothTravel
ctx.EnableAntiAFK       = EnableAntiAFK
ctx.WaitForTrustBuild   = WaitForTrustBuild
ctx.CheckTrustStatus    = CheckTrustStatus
ctx.CollectEgg          = CollectClosestEgg
ctx.HuntNPC             = AutoHuntNPC
end
