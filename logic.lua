-- Steal An Egg - Miracle Hub Logic Module
-- File: logic.lua
-- Implements automation, anti-cheat evasion, and remote management
-- wired against the *real* Steal An Egg client library surface
-- (ReplicatedStorage.Library.Client.* and ReplicatedStorage.Library.*).
--
-- Loader contract (loader.lua): module must `return function(ctx)`.
-- All public functions are written to `ctx` so pages.lua can call them
-- (ctx.EnableSmoothTravel, ctx.CollectEgg, ctx.HuntNPC, ...).

return function(ctx)
local session  = _G._MiracleHubSession

-- ============================================================
-- SERVICE / LIBRARY RESOLUTION
-- ============================================================

local Players           = ctx.Services.Players
local ReplicatedStorage = ctx.Services.ReplicatedStorage
local TweenService     = ctx.Services.TweenService

local localPlayer       = ctx.player
local localPlayerId     = localPlayer and localPlayer.UserId or 0

-- Real game client modules (these are present in ReplicatedStorage).
-- pcall(require, ...) syntax is intentionally wrapped so pcall receives
-- require AND the module path as separate arguments.
local function pcallRequire(path)
    return pcall(function() return require(path) end)
end

local okNet, Network_m              = pcallRequire(ReplicatedStorage:WaitForChild("Library").Client.Network)
local okEgg, EggCmds_m              = pcallRequire(ReplicatedStorage:WaitForChild("Library").Client.EggCmds)
local okAsset, AssetCmds_m          = pcallRequire(ReplicatedStorage:WaitForChild("Library").Client.AssetCmds)
local okMsg, Message_m              = pcallRequire(ReplicatedStorage:WaitForChild("Library").Client.NotificationCmds.Message)
local okBase, BaseUpgradeClient     = pcallRequire(ReplicatedStorage:WaitForChild("Library").Client.BaseUpgradeClient)
local okGuard, ToolGameplayGuard_m  = pcallRequire(ReplicatedStorage:WaitForChild("Library").Client.ToolGameplayGuard)
local okPlot, PlotCmds_m            = pcallRequire(ReplicatedStorage:WaitForChild("Library").Client.PlotCmds)
local okConst, Constants_m          = pcallRequire(ReplicatedStorage:WaitForChild("Library").Globals.Constants)
local okResolver, AssetDnaProductResolver_m = pcallRequire(
    ReplicatedStorage:WaitForChild("Library").Client.AssetDnaProductResolver
)

local NETWORK = (okConst and Constants_m.NETWORK_MAP) or ctx.NETWORK_ENDPOINTS or {}

local function notify(msg, color, dur)
    if okMsg and Message_m and Message_m.Bottom then
        local ok, err = pcall(Message_m.Bottom, {
            Message = msg,
            Time    = dur or 2.5,
            Color   = color or Color3.fromRGB(0, 212, 255),
        })
        if not ok then
            warn("[StealAnEgg] notify failed:", err)
        end
    else
        warn("[StealAnEgg]", msg)
    end
end

local function safeCall(func, ...)
    if type(func) ~= "function" then return false, "NOT_A_FUNCTION" end
    local success, result = pcall(func, ...)
    if not success then
        warn("[StealAnEgg] safeCall:", tostring(result))
    end
    return success, result
end


-- ============================================================
-- UTIL
-- ============================================================

local function getCharacterAndRoot()
    local character = localPlayer and localPlayer.Character
    local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
    local root      = character and character:FindFirstChild("HumanoidRootPart")
    return character, humanoid, root
end

-- Returns a CFrame moved `distance` studs towards `target` from `origin`
-- without teleporting (used by 'approach' helpers).
local function approachCFrame(origin, target, distance)
    if typeof(origin) ~= "CFrame" or typeof(target) ~= "CFrame" then
        return origin
    end
    local dir = (target.Position - origin.Position)
    if dir.Magnitude < 0.01 then return origin end
    return origin + dir.Unit * math.min(distance, dir.Magnitude)
end

local function tweenCFrame(part, cframe, duration)
    if not part or not TweenService then return end
    local t = TweenService:Create(part, TweenInfo.new(duration or 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        CFrame = cframe
    })
    t:Play()
    return t
end

-- Smooth tween of CFrame, yields until completion.
local function tweenCFrameAsync(part, cframe, duration)
    if not part or not TweenService then return end
    local t = TweenService:Create(part, TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        CFrame = cframe
    })
    t:Play()
    t.Completed:Wait()
end

-- ============================================================
-- TRUST / SAFETY DETECTION
-- ============================================================
-- The game does not expose a "trust score" client side. We approximate
-- it from observable state (character alive, server uptime, gameplay area,
-- safe-zone presence) plus an elapsed "warmup" since session start.

local function IsInSafeZone()
    if not okGuard or not ToolGameplayGuard_m then return false end
    local ok, val = pcall(ToolGameplayGuard_m.IsPlayerInTaggedSafeZone, localPlayer)
    return ok and val == true
end

local function IsInGameplayArea()
    if not okGuard or not ToolGameplayGuard_m then return false end
    local ok, val = pcall(ToolGameplayGuard_m.IsLocalPlayerInGameplayArea)
    return ok and val == true
end

local function GetSessionAge()
    if not ctx._SessionStartTime then return 0 end
    return tick() - ctx._SessionStartTime
end

local function CheckTrustStatus()
    -- Approximate trust via: not dead + out of safe zone + warmup time.
    local _, humanoid, _ = getCharacterAndRoot()
    if not humanoid or humanoid.Health <= 0 then
        ctx.RuntimeData.trustScore = 0
        return { status = "dead", score = 0 }
    end

    local inSafe = IsInSafeZone()
    if inSafe then
        ctx.RuntimeData.trustScore = 25
        return { status = "safezone", score = 25 }
    end

    local age = GetSessionAge()
    local warmup = ctx.TRUST_SETTINGS.MIN_TRUST_BUILD_TIME or 5
    if age < warmup then
        local pct = math.floor((age / warmup) * 100)
        ctx.RuntimeData.trustScore = math.clamp(pct, 0, 100)
        return { status = "building", score = ctx.RuntimeData.trustScore }
    end

    ctx.RuntimeData.trustScore = 100
    return { status = "trusted", score = 100 }
end

local function WaitForTrustBuild()
    local maxWait = (ctx.TRUST_SETTINGS.MIN_TRUST_BUILD_TIME or 5) + 2
    local start = tick()
    while tick() - start < maxWait do
        local status = CheckTrustStatus()
        if status.score >= 80 then
            return true
        end
        task.wait(0.4)
    end
    return true
end

-- ============================================================
-- EGG STEAL PIPELINE
-- ============================================================
-- The real game flow for "stealing an area egg" is:
--   1) RequestCarryAreaEgg(Uid)         -> server flips State to "Carried"
--   2) player walks to base (server detects drop on death / rewind / player request)
--   3) Server auto-deposits; UI plays claim feedback.
-- There is NO 'collect' or 'attack' remote: pets in enemy bases are
-- AreaEgg records, and the only legal way to grab one is via the
-- proximity / carry request. We therefore implement auto-steal by
-- walking toward the closest nest of any open area, then calling
-- RequestCarryAreaEgg(Uid).

local function getAllAreaEggs()
    if not okEgg or not EggCmds_m or not EggCmds_m.GetAreaEggSnapshot then return {} end
    local ok, snap = pcall(EggCmds_m.GetAreaEggSnapshot)
    if not ok or type(snap) ~= "table" then return {} end
    return snap.Records or {}
end

local function nearestCarryableEgg(maxDistance)
    local _, _, root = getCharacterAndRoot()
    if not root then return nil, "no_character" end
    local records = getAllAreaEggs()
    if #records == 0 then return nil, "no_records" end

    local best, bestDist = nil, maxDistance or math.huge
    for _, rec in ipairs(records) do
        if rec.State == "Dropped" and rec.BoundsCFrame then
            local dist = (rec.BoundsCFrame.Position - root.Position).Magnitude
            if dist < bestDist then
                best, bestDist = rec, dist
            end
        end
    end
    return best, best and bestDist or nil
end

-- Runs fn protected; preserves ALL return values (unlike bare pcall
-- assignment which truncates to one).
local function protectMulti(fn)
    local packed = table.pack(pcall(fn))
    if not packed[1] then
        warn("[StealAnEgg] protectMulti:", tostring(packed[2]))
        return false, "internal_error"
    end
    return packed[2], packed[3]
end

local function CollectEgg()
    return protectMulti(function()
        if not okEgg or not EggCmds_m or not EggCmds_m.RequestCarryAreaEgg then
            return false, "EggCmds unavailable"
        end
        if not okGuard or not ToolGameplayGuard_m or not ToolGameplayGuard_m.CanActivateLocal() then
            return false, "blocked_by_safezone"
        end

        local record, dist = nearestCarryableEgg()
        if not record then
            return false, "no_carryable_egg"
        end

        local okCarry, errCarry = EggCmds_m.RequestCarryAreaEgg(record.Uid, nil)
        if okCarry == true then
            ctx.RuntimeData.lastStealUid = record.Uid
            return true, dist
        end
        return false, errCarry or "request_failed"
    end)
end

-- ============================================================
-- PET EQUIP / STEAL DNA PIPELINE
-- ============================================================
-- "Auto Hunt" in this game means cycling through OTHER players' pen
-- pets and using the DNA-steal prompt to grab their DNA. The
-- authoritative remote is NetworkMap.ActiveAssets.REQUEST_STEAL_TARGET.
-- We use it to repeatedly request a steal target while the player is
-- near another player's plot.

local function findOtherPlayerPets()
    local records = {}
    if not okAsset or not AssetCmds_m or not AssetCmds_m.GetOwnerRuntimeRecords then
        return records
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer then
            local ok, ownerRecs = pcall(AssetCmds_m.GetOwnerRuntimeRecords, p.UserId)
            if ok and type(ownerRecs) == "table" then
                for _, rec in pairs(ownerRecs) do
                    table.insert(records, rec)
                end
            end
        end
    end
    return records
end

local function HuntNPC()
    return protectMulti(function()
        if not okNet or not Network_m or not Network_m.Invoke then
            return false, "Network unavailable"
        end
        if not okGuard or not ToolGameplayGuard_m or not ToolGameplayGuard_m.CanActivateLocal() then
            return false, "blocked_by_safezone"
        end
        if Constants_m and Constants_m.ASSET_DNA_STEAL_ENABLED == false then
            return false, "dna_steal_disabled_by_game"
        end
        local AA = NETWORK.ActiveAssets
        if not AA or not AA.REQUEST_STEAL_TARGET then
            return false, "endpoint_missing"
        end

        -- Pick the closest visible pet owned by another player.
        local _, _, root = getCharacterAndRoot()
        if not root then return false, "no_character" end

        local pets = findOtherPlayerPets()
        local best = nil
        for _, rec in ipairs(pets) do
            if rec.UID and rec.OwnerUserId then
                -- Runtime asset records do not carry a position; rely on the
                -- server-side distance validation. Prefer any record.
                best = rec
                break
            end
        end
        if not best then return false, "no_pets_visible" end

        -- Resolve steal product id via the game's own resolver when present.
        local productId = nil
        if okResolver and AssetDnaProductResolver_m then
            local okRes, res = pcall(AssetDnaProductResolver_m.GetProductId, best.ItemData)
            if okRes and type(res) == "number" then productId = res end
        end

        -- Network_m.Invoke returns the server payload directly:
        --   success(bool), errMsg(string|nil)  [see AssetInteractionPrompt]
        local success, errMsg
        if productId then
            success, errMsg = Network_m.Invoke(AA.REQUEST_STEAL_TARGET, {
                ProductId   = productId,
                OwnerUserId = best.OwnerUserId,
                UID         = best.UID,
            })
        else
            success, errMsg = Network_m.Invoke(AA.REQUEST_STEAL_TARGET, {
                OwnerUserId = best.OwnerUserId,
                UID         = best.UID,
            })
        end

        if success == true then
            ctx.RuntimeData.lastHuntUid = best.UID
            return true
        end
        return false, errMsg or "steal_target_rejected"
    end)
end

-- ============================================================
-- SMOOTH TRAVEL (gentle walk toward target)
-- ============================================================
-- We avoid rewriting WalkSpeed every frame (that triggers anti-cheat
-- speed-anomaly detection). Instead, we CFrame-tween the root part
-- between waypoints. This is the same technique the in-game
-- "BulkMoveController" uses for animating many pets at once.

local travelActive = false
local travelThread = nil

local function StopTravel()
    travelActive = false
    if travelThread then
        task.cancel(travelThread)
        travelThread = nil
    end
end

local function StartTravelTo(targetCFrame, opts)
    if not targetCFrame or typeof(targetCFrame) ~= "CFrame" then return end
    opts = opts or {}
    StopTravel()
    travelActive = true
    travelThread = task.spawn(function()
        local speed = opts.speed or ctx.TRUST_SETTINGS.SMOOTH_TRAVEL_SPEED or 16
        local stepTime = 0.05
        local stepDist = math.max(2, speed * stepTime)
        while travelActive do
            local _, _, root = getCharacterAndRoot()
            if not root then break end
            local dist = (targetCFrame.Position - root.Position).Magnitude
            if dist < 3 then break end
            local nextCF = approachCFrame(root.CFrame, targetCFrame, stepDist)
            if nextCF ~= root.CFrame then
                tweenCFrame(root, nextCF, stepTime + 0.02)
            end
            task.wait(stepTime)
        end
    end)
end

-- ============================================================
-- ANTI-AFK (subtle idle motion, very low magnitude)
-- ============================================================

local antiAfkActive = false
local antiAfkThread = nil

local function StopAntiAfk()
    antiAfkActive = false
    if antiAfkThread then
        task.cancel(antiAfkThread)
        antiAfkThread = nil
    end
end

local function StartAntiAfk()
    if antiAfkActive then return end
    antiAfkActive = true
    antiAfkThread = task.spawn(function()
        while antiAfkActive and _G._MiracleHubSession == session do
            local _, humanoid, root = getCharacterAndRoot()
            if humanoid and root and humanoid.Health > 0 then
                -- Tiny lateral shift to defeat "didn't move" idle detection.
                local offsetX = (math.random() - 0.5) * 1.2
                local offsetZ = (math.random() - 0.5) * 1.2
                local targetCF = root.CFrame + Vector3.new(offsetX, 0, offsetZ)
                tweenCFrame(root, targetCF, 0.35)
            end
            task.wait(ctx.TRUST_SETTINGS.ANTI_AFK_INTERVAL or 25)
        end
    end)
end

-- ============================================================
-- STEALTH MODE (slow down walkspeed, set anti-cheat evasion)
-- ============================================================
-- The game does not have a client-side "trust" gate that a UI toggle
-- can fool. Stealth mode here just keeps Humanoid.WalkSpeed low and
-- limits how fast the smooth-travel tween moves.

local function EnableSmoothTravel(enabled)
    if enabled and not ctx.States.smoothTravel then
        ctx.States.smoothTravel = true
        print("[StealAnEgg] Smooth Travel ENABLED")
    elseif not enabled and ctx.States.smoothTravel then
        ctx.States.smoothTravel = false
        StopTravel()
        print("[StealAnEgg] Smooth Travel DISABLED")
    end
end

local function EnableAntiAFK(enabled)
    if enabled then
        StartAntiAfk()
        print("[StealAnEgg] Anti-AFK ENABLED")
    else
        StopAntiAfk()
        print("[StealAnEgg] Anti-AFK DISABLED")
    end
end

-- ============================================================
-- FARM LOOP (carries the closest area egg, then waits for server
-- to auto-deposit / repeat)
-- ============================================================

local farmThread = nil
local farmActive = false

local function StartFarmLoop()
    if farmActive then return end
    if not okEgg or not EggCmds_m then
        warn("[StealAnEgg] EggCmds missing - farm disabled")
        return
    end
    -- Safe-zone state is handled inside the loop (pause/resume), so we
    -- intentionally do NOT block startup when standing in spawn.
    farmActive = true
    farmThread = task.spawn(function()
        while farmActive and _G._MiracleHubSession == session do
            local ok, result = CollectEgg()
            if not ok then
                if result == "blocked_by_safezone" then
                    notify("Farm paused: in safe zone", Color3.fromRGB(255, 200, 0), 1.5)
                    task.wait(3)
                elseif result == "no_carryable_egg" then
                    task.wait(2) -- nothing to steal, just wait
                else
                    task.wait(1.5)
                end
            else
                task.wait(0.7)
            end
        end
    end)
end

local function StopFarmLoop()
    farmActive = false
    if farmThread then
        task.cancel(farmThread)
        farmThread = nil
    end
end

-- ============================================================
-- HUNT LOOP (issues DNA-steal requests against visible pen pets)
-- ============================================================

local huntThread = nil
local huntActive = false

local function StartHuntLoop()
    if huntActive then return end
    if not okNet or not Network_m then
        warn("[StealAnEgg] Network missing - hunt disabled")
        return
    end
    huntActive = true
    huntThread = task.spawn(function()
        while huntActive and _G._MiracleHubSession == session do
            local ok, result = HuntNPC()
            if not ok then
                if result == "blocked_by_safezone" then
                    task.wait(3)
                else
                    task.wait(2)
                end
            else
                task.wait(0.5)
            end
        end
    end)
end

local function StopHuntLoop()
    huntActive = false
    if huntThread then
        task.cancel(huntThread)
        huntThread = nil
    end
end

-- ============================================================
-- COLLECT LOOP (auto-equip best pet / open area eggs)
-- ============================================================

local collectThread = nil
local collectActive = false

local function StartCollectLoop()
    if collectActive then return end
    if not okAsset or not AssetCmds_m then return end
    collectActive = true
    collectThread = task.spawn(function()
        while collectActive and _G._MiracleHubSession == session do
            -- Try carrying the closest dropped area egg.
            local okCarry, _ = CollectEgg()
            if not okCarry then task.wait(2) else task.wait(0.6) end
        end
    end)
end

local function StopCollectLoop()
    collectActive = false
    if collectThread then
        task.cancel(collectThread)
        collectThread = nil
    end
end

-- ============================================================
-- HATCH / PLACE / EQUIP HELPERS
-- ============================================================
-- These hook the EggCmds module so the UI buttons can fire real
-- network calls rather than just printing.

local function PlaceHeldEgg(cframe)
    if not okEgg or not EggCmds_m or not EggCmds_m.RequestPlaceEgg then return false, "no_module" end
    local myRecords = {}
    if EggCmds_m.GetOwnerRuntimeRecords then
        local ok, recs = pcall(EggCmds_m.GetOwnerRuntimeRecords, localPlayerId)
        if ok and type(recs) == "table" then myRecords = recs end
    end
    -- Pick the first egg without a placement; default to a spot near the
    -- player (world origin would be rejected by server bounds checks).
    local _, _, root = getCharacterAndRoot()
    local baseCF = (root and CFrame.new(root.Position + Vector3.new(0, 6, 0))) or CFrame.new(0, 10, 0)
    for uid, rec in pairs(myRecords) do
        if not rec.Placement then
            local ok, err = EggCmds_m.RequestPlaceEgg(uid, cframe or baseCF)
            return ok == true, err
        end
    end
    return false, "no_unplaced_egg"
end

local function HatchReadyEggs()
    if not okEgg or not EggCmds_m then return 0 end
    local myRecords = {}
    if EggCmds_m.GetOwnerRuntimeRecords then
        local ok, recs = pcall(EggCmds_m.GetOwnerRuntimeRecords, localPlayerId)
        if ok and type(recs) == "table" then myRecords = recs end
    end
    local hatched = 0
    for uid, rec in pairs(myRecords) do
        if rec.Placement and EggCmds_m.IsLocalEggReady and EggCmds_m.IsLocalEggReady(uid) then
            local ok, _ = EggCmds_m.RequestHatchEgg(uid)
            if ok == true then
                hatched = hatched + 1
            end
        end
    end
    return hatched
end

local function SkipGrowthForAll()
    if not okEgg or not EggCmds_m or not EggCmds_m.RequestSkipGrowth then return 0 end
    local myRecords = {}
    if EggCmds_m.GetOwnerRuntimeRecords then
        local ok, recs = pcall(EggCmds_m.GetOwnerRuntimeRecords, localPlayerId)
        if ok and type(recs) == "table" then myRecords = recs end
    end
    local skipped = 0
    for uid, rec in pairs(myRecords) do
        if rec.Placement and not (EggCmds_m.IsLocalEggReady and EggCmds_m.IsLocalEggReady(uid)) then
            local ok, _ = EggCmds_m.RequestSkipGrowth(uid)
            if ok == true then skipped = skipped + 1 end
        end
    end
    return skipped
end

local function UpgradeBase()
    if not okBase or not BaseUpgradeClient or not BaseUpgradeClient.RequestCashUpgrade then
        return false, "BaseUpgradeClient unavailable"
    end
    return BaseUpgradeClient.RequestCashUpgrade() == true
end

-- ============================================================
-- PUBLIC TOGGLES (called from pages.lua)
-- ============================================================

function ctx.SetAutoFarm(state)
    ctx.States.autoFarm = state and true or false
    if state then StartFarmLoop() else StopFarmLoop() end
end

function ctx.SetAutoHunt(state)
    ctx.States.autoHunt = state and true or false
    if state then StartHuntLoop() else StopHuntLoop() end
end

function ctx.SetAutoCollect(state)
    ctx.States.autoCollect = state and true or false
    if state then StartCollectLoop() else StopCollectLoop() end
end

function ctx.SetStealth(state)
    ctx.States.stealthMode = state and true or false
    -- Stealth keeps smooth travel tween slow.
    if ctx.TRUST_SETTINGS then
        ctx.TRUST_SETTINGS.SMOOTH_TRAVEL_SPEED = ctx.States.stealthMode and 12 or 18
    end
end

function ctx.TeleportToBase()
    if not okPlot or not PlotCmds_m or not PlotCmds_m.GetRespawnPointCFrame then
        return false, "PlotCmds unavailable"
    end
    local ok, cf = pcall(PlotCmds_m.GetRespawnPointCFrame)
    if not ok or typeof(cf) ~= "CFrame" then return false, "no_respawn" end
    local _, _, root = getCharacterAndRoot()
    if not root then return false, "no_character" end
    tweenCFrameAsync(root, cf, 0.4)
    return true
end

-- ============================================================
-- SESSION CLEANUP
-- ============================================================

local CleanupRoutine = function()
    StopFarmLoop()
    StopHuntLoop()
    StopCollectLoop()
    StopAntiAfk()
    StopTravel()
    ctx.States.enabled    = false
    ctx.States.autoFarm   = false
    ctx.States.autoHunt   = false
    ctx.States.autoCollect = false
    ctx.States.smoothTravel = false
    ctx.States.antiAFK = false
end

_G.GameCleanup = _G.GameCleanup or {}
table.insert(_G.GameCleanup, CleanupRoutine)

-- ============================================================
-- EXPORT PUBLIC API
-- ============================================================

ctx.FireRemote          = function(name, ...)
    if not okNet or not Network_m then return false, "Network unavailable" end
    return pcall(Network_m.Fire, name, ...)
end

ctx.EnableSmoothTravel  = EnableSmoothTravel
ctx.EnableAntiAFK       = EnableAntiAFK
ctx.WaitForTrustBuild   = WaitForTrustBuild
ctx.CheckTrustStatus    = CheckTrustStatus

ctx.CollectEgg          = CollectEgg
ctx.HuntNPC             = HuntNPC
ctx.PlaceHeldEgg        = PlaceHeldEgg
ctx.HatchReadyEggs      = HatchReadyEggs
ctx.SkipGrowthForAll    = SkipGrowthForAll
ctx.UpgradeBase         = UpgradeBase

ctx.GetAreaEggs         = getAllAreaEggs
ctx.GetOtherPlayerPets  = findOtherPlayerPets
ctx.IsInSafeZone        = IsInSafeZone
ctx.IsInGameplayArea    = IsInGameplayArea
ctx.SafeCall            = safeCall
ctx.Notify              = notify

print("[MiracleHub] Steal An Egg Logic Initialized | Session:", session)
end
