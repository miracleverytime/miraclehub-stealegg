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

-- Real game client modules.
-- IMPORTANT: instance resolution happens INSIDE the protected call.
-- Evaluating `A.B.C` as an argument would throw BEFORE pcall engages
-- and abort the whole hub load chain; a missing module must instead
-- degrade gracefully to (false, nil).
local Lib    = ReplicatedStorage:WaitForChild("Library", 30)
local Client = Lib and Lib:FindFirstChild("Client")

local function loadModule(resolveFn)
    if not Client then return false, nil end
    local ok, result = pcall(resolveFn)
    if not ok then
        warn("[StealAnEgg] module skipped:", tostring(result))
        return false, nil
    end
    return true, result
end

local okNet, Network_m              = loadModule(function() return require(Client.Network) end)
local okEgg, EggCmds_m              = loadModule(function() return require(Client.EggCmds) end)
local okAsset, AssetCmds_m          = loadModule(function() return require(Client.AssetCmds) end)
local okMsg, Message_m              = loadModule(function() return require(Client.NotificationCmds.Message) end)
local okBase, BaseUpgradeClient     = loadModule(function() return require(Client.BaseUpgradeClient) end)
local okGuard, ToolGameplayGuard_m  = loadModule(function() return require(Client.ToolGameplayGuard) end)
local okPlot, PlotCmds_m            = loadModule(function() return require(Client.PlotCmds) end)

-- Lives under PlayerScripts.Game.Plots.ActiveAssetsController,
-- NOT ReplicatedStorage.Library.Client.
local okResolver, AssetDnaProductResolver_m = (function()
    local ps  = localPlayer:FindFirstChild("PlayerScripts")
    local g   = ps and ps:FindFirstChild("Game")
    local pl  = g and g:FindFirstChild("Plots")
    local aac = pl and pl:FindFirstChild("ActiveAssetsController")
    local m   = aac and aac:FindFirstChild("AssetDnaProductResolver")
    if not m then return false, nil end
    return pcall(function() return require(m) end)
end)()

local Globals = Lib and Lib:FindFirstChild("Globals")
local okConst, Constants_m = loadModule(function()
    if not Globals then error("Library.Globals missing") end
    return require(Globals.Constants)
end)

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
    if okEggState and EggState_m and EggState_m.ReadFieldEggs then
        local ok, snap = pcall(EggState_m.ReadFieldEggs)
        if ok and type(snap) == "table" and snap.Records then
            return snap.Records
        end
    end
    if okEgg and EggCmds_m and EggCmds_m.GetAreaEggSnapshot then
        local ok, snap = pcall(EggCmds_m.GetAreaEggSnapshot)
        if ok and type(snap) == "table" and snap.Records then
            return snap.Records
        end
    end
    return {}
end

-- True if this is one of the local player's own "FirstAreaEgg_<uid>_..." starter eggs
-- (those sit in the player's own nest and must NOT be "collected").
local function isFirstAreaOwnEgg(uid)
    local owner = string.match(uid or "", "^FirstAreaEgg_(-?%d+)_")
    return owner ~= nil and tonumber(owner) == localPlayerId
end

local function nearestCarryableEgg(maxDistance)
    local _, _, root = getCharacterAndRoot()
    if not root then return nil, "no_character" end
    local records = getAllAreaEggs()
    if #records == 0 then return nil, "no_records" end

    local best, bestDist = nil, maxDistance or math.huge
    for _, rec in ipairs(records) do
        local stealable = rec.State == "Slot" or rec.State == "Dropped"
        if stealable and rec.BoundsCFrame and not isFirstAreaOwnEgg(rec.Uid) then
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

-- Forward declarations (StartTravelTo/StopTravel are defined later in the
-- SMOOTH TRAVEL section; these let CollectEgg reference them as upvalues).
local StartTravelTo, StopTravel

-- ============================================================
-- AUTO STEAL EGG v2 (tween ke egg -> ambil -> bawa ke base)
-- ============================================================
-- Engine yang sama persis dengan yang sudah diuji live (8 egg sukses).
-- Memakai modul asli game: ReplicatedStorage.Client.EggState,
-- Shared.Util.AreaEggSlotIdentity, Client.PlotState.

local okEggState, EggState_m = (function()
    -- JANGAN pakai loadModule: guard `if not Client` memblokir karena game ini
    -- tidak punya folder ReplicatedStorage.Library. Module asli ada di
    -- ReplicatedStorage.Client / ReplicatedStorage.Shared.
    if not ReplicatedStorage then return false, nil end
    return pcall(function() return require(ReplicatedStorage.Client.EggState) end)
end)()
local okSlotId, AreaEggSlotIdentity_m = (function()
    if not ReplicatedStorage then return false, nil end
    return pcall(function() return require(ReplicatedStorage.Shared.Util.AreaEggSlotIdentity) end)
end)()
local okPlot, PlotState_m = (function()
    if not ReplicatedStorage then return false, nil end
    return pcall(function() return require(ReplicatedStorage.Client.PlotState) end)
end)()

local okTreadmillUtil, TreadmillUtil_m = (function()
    if not ReplicatedStorage then return false, nil end
    return pcall(function() return require(ReplicatedStorage.Shared.Util.TreadmillUtil) end)
end)()
local okSave, Save_m = (function()
    if not ReplicatedStorage then return false, nil end
    return pcall(function() return require(ReplicatedStorage.Shared.Save) end)
end)()

-- Helper untuk mendapatkan kecepatan WalkSpeed (Max hard-cap game adalah 300)
local function getNaturalWalkSpeed()
    -- Jika toggle dynamic speed aktif, kita langsung berikan batas maksimal game (300 studs/s)
    if ctx.States.stealDynamicSpeed ~= false then
        return 300
    end
    -- Jika custom slider diatur
    if ctx.States.stealTweenSpeed then
        return ctx.States.stealTweenSpeed
    end
    -- Fallback ke SpeedPower akun
    if okTreadmillUtil and TreadmillUtil_m and okSave and Save_m then
        local ok, data = pcall(function()
            if Save_m.ReadUnguarded then
                return Save_m.ReadUnguarded()
            elseif Save_m.GetSaveData then
                return Save_m.GetSaveData()
            end
            return nil
        end)
        if ok and type(data) == "table" and data.SpeedPower then
            local okWS, ws = pcall(TreadmillUtil_m.SpeedPowerToWalkSpeed, data.SpeedPower)
            if okWS and type(ws) == "number" and ws > 0 then
                return ws
            end
        end
    end
    local _, hum = getCharacterAndRoot()
    return (hum and hum.WalkSpeed > 0) and hum.WalkSpeed or 16
end

local stealActive = false
local stealThread = nil

-- Gerak menuju posisi target menggunakan Humanoid:MoveTo + dynamic velocity propulsion (hingga 300 studs/s).
-- Memberikan pergerakan mulus & cepat dengan physics resmi tanpa rubberband server.
-- opts.onStep() dipanggil tiap langkah; kembalikan true untuk membatalkan
-- (mis. egg jatuh di tengah jalan) — tween berhenti & return false.
local function stealTweenTo(pos, heightOffset, opts)
    opts = opts or {}
    local _, hum, root = getCharacterAndRoot()
    if not root or not hum then return false end
    if hum.Health <= 0 then return false end

    local target = pos + Vector3.new(0, heightOffset or 4, 0)
    local dist = (target - root.Position).Magnitude
    if dist < 3 then
        root.CFrame = CFrame.lookAt(target, pos)
        return true
    end

    local targetSpeed = 300
    if ctx.States.stealDynamicSpeed == false and ctx.States.stealTweenSpeed then
        targetSpeed = ctx.States.stealTweenSpeed
    end
    targetSpeed = math.clamp(targetSpeed, 16, 300)

    -- Set WalkSpeed
    if math.abs(hum.WalkSpeed - targetSpeed) > 1 then
        pcall(function() hum.WalkSpeed = targetSpeed end)
    end

    local arrived = false
    local timeout = (dist / targetSpeed) + 8
    local t0 = os.clock()

    while stealActive and os.clock() - t0 < timeout do
        _, hum, root = getCharacterAndRoot()
        if not root or not hum or hum.Health <= 0 then break end

        -- pembatalan (drop detection) — berhenti segera & hentikan gerak
        if opts.onStep and opts.onStep() then
            pcall(function() hum:MoveTo(root.Position) end)
            return false
        end

        local delta = (target - root.Position)
        local flatDist = Vector3.new(delta.X, 0, delta.Z).Magnitude
        if flatDist < 6 then
            arrived = true
            break
        end

        local dir = delta.Unit
        hum:MoveTo(target)

        -- Dorongan akselerasi AssemblyLinearVelocity agar mencapai kecepatan target (hingga 300 studs/s)
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.new(
                dir.X * targetSpeed,
                root.AssemblyLinearVelocity.Y,
                dir.Z * targetSpeed
            )
        end)

        task.wait(0.03)
    end

    pcall(function()
        if hum and hum.Parent then hum:MoveTo(root.Position) end
    end)
    _, _, root = getCharacterAndRoot()
    if arrived or (root ~= nil and (root.Position - target).Magnitude < 6) then
        return true
    end
    return false
end

-- Resolusi plot milik player (pet area = titik drop aman).
local function stealGetPetArea()
    if not okPlot or not PlotState_m then return nil end
    local ok2, plot = pcall(PlotState_m.ResolvePlot, localPlayer)
    if ok2 and type(plot) == "table" and plot.PetArea and plot.PetArea:IsA("BasePart") then
        return plot.PetArea
    end
    return nil
end

-- Target "safe zone": sisi base di belakang garis pemisah (x < SeparationLine),
-- tetap dekat gate supaya server langsung menghitung player sudah keluar dari
-- gameplay area dan meng-claim egg. Menghindari menyentuh treadmill/PetArea.
local function stealGetSafeZoneTarget()
    local areas = workspace and workspace:FindFirstChild("__OBJECTS") and workspace.__OBJECTS:FindFirstChild("Areas")
    local sep = areas and areas:FindFirstChild("SeparationLine")
    if sep and sep:IsA("BasePart") then
        -- belok 6 stud ke arah base dari garis, sejajar ketinggian normal
        local back = sep.Position - sep.CFrame.LookVector * 6
        return Vector3.new(back.X, back.Y + 2, back.Z)
    end
    -- fallback: ke arah plot (beberapa stud dari garis pemisah)
    local _, _, root = getCharacterAndRoot()
    if root then
        return root.Position - Vector3.new(30, 0, 0)
    end
    return nil
end

-- Egg terdekat yang bisa diambil (State Slot ATAU Dropped).
-- Dropped = egg yang jatuh (mis. kena penjaga) -> harus diambil ULANG dulu.
-- stealRetargetUid = egg yang baru jatuh; diprioritaskan agar diambil balik.
local stealRetargetUid = nil

local function stealFindTarget(root)
    if not okEggState or not EggState_m or not EggState_m.ReadFieldEggs then return nil end
    local filter = ctx.States.stealAreaFilter or ""
    local preferFirst = ctx.States.stealPreferFirst ~= false
    local best, bestD = nil, math.huge
    local bestFirst, bestFirstD = nil, math.huge
    local ok, rows = pcall(function() return EggState_m.ReadFieldEggs() end)
    if not ok or type(rows) ~= "table" then return nil end

    -- 1) Prioritas mutlak: egg yang baru saja jatuh (kita harus ambil balik dulu)
    if stealRetargetUid then
        for _, r in ipairs(rows.Records or {}) do
            if r.Uid == stealRetargetUid and r.BottomCFrame
                and (r.State == "Dropped" or r.State == "Slot") then
                return r
            end
        end
        stealRetargetUid = nil -- egg itu hilang; reset
    end

    -- 2) Egg terdekat. Dropped (egg yang jatuh) diprioritaskan di atas Slot,
    --    karena harus diambil ulang secepatnya sebelum dipungut orang lain.
    local bestDrop, bestDropD = nil, math.huge
    local bestFirst, bestFirstD = nil, math.huge
    for _, r in ipairs(rows.Records or {}) do
        if (r.State == "Slot" or r.State == "Dropped") and r.BottomCFrame then
            if filter == "" or r.AreaId == filter then
                local d = (r.BottomCFrame.Position - root.Position).Magnitude
                local isFirst = okSlotId and AreaEggSlotIdentity_m.LooksLikeFirstAreaUid(r.Uid)
                if isFirst then
                    if d < bestFirstD then bestFirstD, bestFirst = d, r end
                elseif r.State == "Dropped" then
                    if d < bestDropD then bestDropD, bestDrop = d, r end
                elseif d < bestD then
                    bestD, best = d, r
                end
            end
        end
    end
    if bestDrop then return bestDrop end
    if preferFirst and bestFirst then return bestFirst end
    return best
end

-- Apakah player sedang membawa egg (record State = Carried milik kita).
local function stealIsCarrying()
    if not okEggState or not EggState_m then return false end
    local ok, rows = pcall(function() return EggState_m.ReadFieldEggs() end)
    if not ok or type(rows) ~= "table" then return false end
    for _, r in ipairs(rows.Records or {}) do
        if r.State == "Carried" and r.CarrierUserId == localPlayerId then
            return true
        end
    end
    return false
end

-- Uid egg yang sedang dibawa (untuk deteksi jatuh saat dibawa pulang).
local function stealGetCarriedUid()
    if not okEggState or not EggState_m then return nil end
    local ok, rows = pcall(function() return EggState_m.ReadFieldEggs() end)
    if not ok or type(rows) ~= "table" then return nil end
    for _, r in ipairs(rows.Records or {}) do
        if r.State == "Carried" and r.CarrierUserId == localPlayerId then
            return r.Uid
        end
    end
    return nil
end

-- Uid egg yang DROPPED (baru saja jatuh, mis. kena penjaga). Bila sedang
-- membawa uid A dan tiba-tiba ada egg Dropped milik perjalanan kita, ini
-- menandakan egg A jatuh -> harus diambil ulang.
local function stealGetDroppedUid(carriedUid)
    if not okEggState or not EggState_m then return nil end
    local ok, rows = pcall(function() return EggState_m.ReadFieldEggs() end)
    if not ok or type(rows) ~= "table" then return nil end
    local _, _, root = getCharacterAndRoot()
    for _, r in ipairs(rows.Records or {}) do
        if r.State == "Dropped" and r.BottomCFrame then
            if carriedUid and r.Uid == carriedUid then
                return r.Uid
            end
            -- egg Dropped lain yang posisinya di dekat kita (baru jatuh)
            if root and (r.BottomCFrame.Position - root.Position).Magnitude < 25 then
                return r.Uid
            end
        end
    end
    return nil
end

-- Invoke carry dengan watchdog (anti-hang saat koneksi drop).
local function stealSafeCarry(rec)
    if not okEggState or not EggState_m or not EggState_m.CarryFieldEgg then return false, "no_module" end
    local slotKey = nil
    if okSlotId and AreaEggSlotIdentity_m and AreaEggSlotIdentity_m.LooksLikeFirstAreaUid(rec.Uid) then
        local okK, key = pcall(AreaEggSlotIdentity_m.SlotKey, rec.AreaId, rec.NestId)
        if okK then slotKey = key end
    end
    pcall(function() localPlayer:SetAttribute("AreaId", rec.AreaId) end)
    task.wait(0.2)
    local result, done = nil, false
    local th = task.spawn(function()
        local success, okBool, errMsg = pcall(EggState_m.CarryFieldEgg, rec.Uid, slotKey)
        if not success then
            result = { ok = false, err = tostring(okBool) }
        else
            result = { ok = okBool == true, err = okBool == true and nil or tostring(errMsg) }
        end
        done = true
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < 10 do task.wait(0.05) end
    if not done then
        pcall(task.cancel, th)
        return false, "TIMEOUT"
    end
    if not result.ok then return false, result.err end
    return true, nil
end

local function stealUnequip()
    local _, hum = getCharacterAndRoot()
    if hum then pcall(hum.UnequipTools) end
end

-- Sisi "base" adalah x < SeparationLine; area gameplay x > line.
-- Server baru mencatat player "masuk gameplay area" saat karakter MENYEBERANG
-- fisik lewat gate (GameplayZ), bukan saat teleport. Bila carry ditolak
-- "Enter the gameplay area first", arahkan karakter menyusuri titik gate
-- dari sisi base lalu maju melintas (MoveTo = physics asli, Touched terpicu).
local function stealEnterGameplayArea()
    local _, _, root = getCharacterAndRoot()
    local hum = nil
    if localPlayer and localPlayer.Character then
        hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
    end
    if not root or not hum then return false end
    local areas = workspace and workspace:FindFirstChild("__OBJECTS") and workspace.__OBJECTS:FindFirstChild("Areas")
    local sep = areas and areas:FindFirstChild("SeparationLine")
    if not sep or not sep:IsA("BasePart") then return false end
    local gate = sep.Position + Vector3.new(0, 2, 0) + sep.CFrame.LookVector * 2
    local gateBack = sep.Position + Vector3.new(0, 2, 0) - sep.CFrame.LookVector * 6
    local naturalWS = getNaturalWalkSpeed()
    hum.WalkSpeed = math.max(naturalWS, 45)
    -- 1) berdiri di sisi base dulu (dekat gate, sebelum garis)
    local _, _, r2 = getCharacterAndRoot()
    if r2 and (r2.Position - gateBack).Magnitude > 3 then
        r2.CFrame = CFrame.lookAt(gateBack, gate)
        task.wait(0.3)
    end
    -- 2) jalan melewati gate ke sisi gameplay
    hum:MoveTo(gate)
    local t0 = os.clock()
    while os.clock() - t0 < 8 do
        task.wait(0.05)
        local _, _, r3 = getCharacterAndRoot()
        if not r3 then break end
        if (r3.Position - gate).Magnitude < 3 then break end
    end
    hum:MoveTo(gate + sep.CFrame.LookVector * 5)
    task.wait(0.8)
    return true
end

local function StartStealLoop()
    if stealActive then return end
    if not okEggState or not EggState_m then
        warn("[StealAnEgg] EggState missing - auto steal disabled")
        return
    end
    stealActive = true
    stealThread = task.spawn(function()
        notify("Auto Steal", "Engine started (tween -> carry -> safe zone)", Color3.fromRGB(77, 214, 201), 2)
        while stealActive and _G._MiracleHubSession == session do
            local ok2, res = pcall(function()
                local _, _, root = getCharacterAndRoot()
                if not root then return "no_character" end
                if stealIsCarrying() then
                    -- Tween ke SAFE ZONE (belakang garis pemisah), bukan ke PetArea.
                    -- Server meng-claim egg otomatis saat pembawa masuk safe zone.
                    local carriedUid = stealGetCarriedUid()
                    local sz = stealGetSafeZoneTarget()
                    if not sz then return "no_safe_zone" end
                    stealUnequip()
                    -- onStep: batalkan MoveTo SEGERA bila egg tidak lagi dibawa (jatuh/kena penjaga)
                    local droppedEarly = false
                    stealTweenTo(sz, 2, {
                        onStep = function()
                            -- 1. Cek langsung apakah status carried lepas
                            if not stealIsCarrying() then
                                droppedEarly = true
                                return true -- cancel move
                            end
                            -- 2. Cek apakah ada record dropped
                            if stealGetDroppedUid(carriedUid) then
                                droppedEarly = true
                                return true -- cancel move
                            end
                            return false
                        end,
                    })
                    if droppedEarly or not stealIsCarrying() then
                        local droppedUid = stealGetDroppedUid(carriedUid) or carriedUid
                        stealRetargetUid = droppedUid
                        notify("Auto Steal", "Egg terlepas/jatuh! Putar balik ambil ulang...", Color3.fromRGB(251, 191, 36), 2)
                        stealUnequip()
                        task.wait(0.3)
                    else
                        -- tunggu claim server (record Carried hilang)
                        local t0 = os.clock()
                        while stealActive and os.clock() - t0 < 25 do
                            if not stealIsCarrying() then break end
                            task.wait(0.1)
                        end
                        if not stealIsCarrying() then
                            -- Cek apakah egg TADI di-drop (kena penjaga) bukan di-claim.
                            -- Dropped: harus diambil ulang DULU, jangan dianggap sukses.
                            local dropped = false
                            local stillExists = false
                            if carriedUid and okEggState and EggState_m then
                                local okR, rows = pcall(function() return EggState_m.ReadFieldEggs() end)
                                if okR and type(rows) == "table" then
                                    for _, r in ipairs(rows.Records or {}) do
                                        if r.Uid == carriedUid then
                                            stillExists = true
                                            if r.State == "Dropped" then
                                                dropped = true
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                            if dropped then
                                stealRetargetUid = carriedUid
                                notify("Auto Steal", "Egg jatuh di dekat garis! Mengambil ulang...", Color3.fromRGB(251, 191, 36), 2)
                            else
                                ctx.RuntimeData.stealStolen = (ctx.RuntimeData.stealStolen or 0) + 1
                                notify("Auto Steal", "Egg delivered (safe zone)! Total: " .. tostring(ctx.RuntimeData.stealStolen), Color3.fromRGB(77, 214, 201), 2)
                            end
                        else
                            if okEggState and EggState_m and EggState_m.DropFieldEgg then
                                pcall(function() EggState_m.DropFieldEgg(nil) end)
                            end
                        end
                        stealUnequip()
                        task.wait(1)
                    end
                else
                    local target = stealFindTarget(root)
                    if not target then
                        task.wait(2)
                    else
                        if stealTweenTo(target.BottomCFrame.Position, 4) then
                            local okC, errC = stealSafeCarry(target)
                            if okC then
                                notify("Auto Steal", "Egg taken: " .. tostring(target.AssetCategory or target.Uid), Color3.fromRGB(251, 191, 36), 1.5)
                            else
                                -- Bila server belum mencatat "masuk gameplay area",
                                -- lintasi gate fisik lalu coba sekali lagi.
                                if errC and tostring(errC):find("gameplay area") then
                                    stealEnterGameplayArea()
                                    local okC2, errC2 = stealSafeCarry(target)
                                    if okC2 then
                                        notify("Auto Steal", "Egg taken: " .. tostring(target.AssetCategory or target.Uid), Color3.fromRGB(251, 191, 36), 1.5)
                                    else
                                        ctx.RuntimeData.stealFailed = (ctx.RuntimeData.stealFailed or 0) + 1
                                        task.wait(1)
                                    end
                                else
                                    ctx.RuntimeData.stealFailed = (ctx.RuntimeData.stealFailed or 0) + 1
                                    if errC ~= "no_carryable" then task.wait(1) end
                                end
                            end
                        end
                    end
                end
                return "ok"
            end)
            if type(res) == "string" then
                if res == "no_character" then task.wait(1) end
            end
            task.wait(0.1)
        end
    end)
end

local function StopStealLoop()
    stealActive = false
    if stealThread then
        task.cancel(stealThread)
        stealThread = nil
    end
end

function ctx.SetAutoSteal(state)
    ctx.States.autoSteal = state and true or false
    if state then StartStealLoop() else StopStealLoop() end
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

StopTravel = function()
    travelActive = false
    if travelThread then
        task.cancel(travelThread)
        travelThread = nil
    end
end

StartTravelTo = function(targetCFrame, opts)
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
-- AUTO FARM (alias for Auto Steal)
-- ============================================================

function ctx.SetAutoFarm(state)
    ctx.States.autoFarm = state and true or false
    if ctx.SetAutoSteal then
        ctx.SetAutoSteal(state)
    end
end

-- ============================================================
-- HATCH / PLACE / EQUIP HELPERS
-- ============================================================
-- These hook the EggCmds module so the UI buttons can fire real
-- network calls rather than just printing.

local function HatchReadyEggs()
    if not okEggState or not EggState_m then return 0 end
    local myRecords = {}
    if EggState_m.ReadOwnedEggs then
        local ok, recs = pcall(EggState_m.ReadOwnedEggs)
        if ok and type(recs) == "table" then myRecords = recs end
    end
    local hatched = 0
    for uid, rec in pairs(myRecords) do
        if EggState_m.IsReadyToHatch and EggState_m.IsReadyToHatch(uid) then
            if EggState_m.BeginHatch then
                local ok, _ = pcall(EggState_m.BeginHatch, uid)
                if ok then hatched = hatched + 1 end
            end
        end
    end
    return hatched
end

local function SkipGrowthForAll()
    if not okEggState or not EggState_m or not EggState_m.BeginSkipGrowth then return 0 end
    local myRecords = {}
    if EggState_m.ReadOwnedEggs then
        local ok, recs = pcall(EggState_m.ReadOwnedEggs)
        if ok and type(recs) == "table" then myRecords = recs end
    end
    local skipped = 0
    for uid, rec in pairs(myRecords) do
        local ok, _ = pcall(EggState_m.BeginSkipGrowth, uid)
        if ok then skipped = skipped + 1 end
    end
    return skipped
end

local function UpgradeBase()
    local okClient, BaseUpgrade_m = pcall(function()
        return require(ReplicatedStorage.Client.BaseUpgrade)
    end)
    if okClient and BaseUpgrade_m and BaseUpgrade_m.PurchaseNextTier then
        local ok, res = pcall(BaseUpgrade_m.PurchaseNextTier)
        return ok and res == true
    end
    if okBase and BaseUpgradeClient and BaseUpgradeClient.RequestCashUpgrade then
        return BaseUpgradeClient.RequestCashUpgrade() == true
    end
    return false, "BaseUpgrade unavailable"
end

-- ============================================================
-- PUBLIC TOGGLES (called from pages.lua)
-- ============================================================

function ctx.SetAutoFarm(state)
    ctx.States.autoFarm = state and true or false
    if ctx.SetAutoSteal then
        ctx.SetAutoSteal(state)
    end
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
    StopStealLoop()
    StopAntiAfk()
    StopTravel()
    ctx.States.enabled    = false
    ctx.States.autoSteal  = false
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

ctx.HatchReadyEggs      = HatchReadyEggs
ctx.SkipGrowthForAll    = SkipGrowthForAll
ctx.UpgradeBase         = UpgradeBase

ctx.GetAreaEggs         = getAllAreaEggs
ctx.IsInSafeZone        = IsInSafeZone
ctx.IsInGameplayArea    = IsInGameplayArea
ctx.SafeCall            = safeCall
ctx.Notify              = notify

print("[MiracleHub] Steal An Egg Logic Initialized | Session:", session)
end
