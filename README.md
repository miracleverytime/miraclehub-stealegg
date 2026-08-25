# 🥚 Miracle Hub - Steal An Egg

> **Universal Roblox Exploit Hub** dengan anti-cheat evasion berbasis trust system

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![PlaceId](https://img.shields.io/badge/PlaceId-107778070777162-orange.svg)](rbx://107778070777162)
[![MiracleHub](https://img.shields.io/badge/MiracleHub-v5.0-green.svg)](https://github.com/miracleverytime/miraclehub-shared)

---

## 🎯 Features

### **Anti-Cheat Evasion Systems**

| System | Status | Description |
|--------|--------|-------------|
| **Trust Building** | ✅ Active | 5-second warmup sebelum automation aktif |
| **Movement Validation** | ✅ Bypass | Smooth velocity interpolation, no teleport |
| **Guard Tutorial Awareness** | ✅ Respected | Pause actions saat guard validation aktif |
| **AdminAbuse Monitoring** | ✅ Aware | Monitor event cooldowns |
| **Stealth Mode** | ✅ Default | Speed modulation until trust ≥80% |
| **Anti-AFK Protection** | ✅ Built-in | Random movements every 30s |

### **Automation Modules**

#### ⛏️ Auto Farm
- **Auto Collect Eggs** - Proximity-based collection dengan trust-safe approach
- **Auto Hunt NPCs** - Combat automation dengan range check
- **Smart Targeting** - Prioritize closest targets first

#### 🥚 Egg Tracker
- **Dynamic Detection** - Real-time egg location scanning
- **Rarity Priority** - Multi-select preferred egg types
- **Collection History** - Track collected eggs (runtime feature)

#### 🚶 Movement Systems
- **Smooth Travel** - Gradual speed adjustment (no instant teleport)
- **Trust Optimization** - WalkSpeed variation within safe envelope
- **Anti-Freeze** - Prevent trust score from freezing

---

## 📦 Installation

### **Method 1: Universal Loader (Recommended)**

Inject sekali ini saja di Roblox console atau script executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/miracleverytime/miraclehub-shared/main/loader.lua"))()
```

Script akan auto-detect **PlaceId: 107778070777162** dan load module secara otomatis.

### **Method 2: Manual Injection**

Jika ingin load manual (tidak pakai universal loader):

```lua
-- Load core configuration
loadstring(game:HttpGet("https://raw.githubusercontent.com/miracleverytime/MiracleHub-SteaLEgg/main/core.lua"))()

-- Load logic module  
loadstring(game:HttpGet("https://raw.githubusercontent.com/miracleverytime/MiracleHub-SteaLEgg/main/logic.lua"))(ctx)

-- Load pages UI
loadstring(game:HttpGet("https://raw.githubusercontent.com/miracleverytime/MiracleHub-SteaLEgg/main/pages.lua"))(ctx)
```

---

## 🎮 Usage Guide

### **First Time Setup**

1. **Join Game** - Masuk ke server Steal An Egg
2. **Wait Trust Build** - Diam sebentar (5 detik) untuk trust building
3. **Inject Script** - Jalankan universal loader
4. **Check Trust Score** - Lihat score di Home tab (harus ≥80%)
5. **Enable Stealth Mode** - Aktifkan toggle "🔒 Stealth Mode"
6. **Start Automation** - Enable "ENABLE Auto Farm"

### **Best Practices**

✅ **DO:**
- Always enable stealth mode for maximum safety
- Wait for trust score ≥80% before heavy actions
- Stand still after respawn/reconnect to rebuild trust
- Use anti-AFK to maintain movement history

❌ **DON'T:**
- Rapidly change speeds during trust-building phase
- Instant teleport large distances
- Disable gravity while moving
- Spam actions faster than 0.5s interval

### **Emergency Actions**

If suspicious activity detected:
1. Click **"🚨 EMERGENCY DISABLE"** button
2. Stand still for 10-15 seconds
3. Wait for trust score recovery
4. Re-enable with caution

---

## 🔧 Configuration

### **Trust Settings (core.lua)**

Adjust these values in `core.lua` untuk custom trust behavior:

```lua
TRUST_SETTINGS = {
    ENABLE_SMOOTH_MOVEMENT = true,        -- Enable/disable smooth movement
    MAX_WALK_SPEED_VARIATION = 0.5,       -- Max walkspeed change per second
    MAX_JUMP_HEIGHT_VARIATION = 1.2,      -- Max jump height deviation
    MIN_TRUST_BUILD_TIME = 5,             -- Seconds before automation can start
    SMOOTH_TRAVEL_SPEED = 1.5,            -- Travel speed multiplier
    ANTI_AFK_INTERVAL = 30,               -- Seconds between valid movements
}
```

### **UI Keybinds (configurable via shared framework)**

- **Toggle Menu:** [Insert] (default)
- **Trust Check:** [F] (customizable)
- **Emergency Disable:** [X] (customizable)

---

## 🛡️ Safety Features

### **PCall Protection**
All remote function calls wrapped in error handlers:
```lua
local FireRemoteAsync = function(remoteNameOrPath, ...args)
    local success, result = pcall(function()
        if remote:IsA("RemoteFunction") then
            return remote:InvokeServer(unpack(args))
        end
    end)
    return success, result
end
```

### **Session Guards**
All loops use session verification:
```lua
while _G._MiracleHubSession == SESSION do
    -- Automation logic
    task.wait(delay)
end
```

### **Cleanup Hooks**
Proper cleanup on unload:
```lua
_G.GameCleanup = _G.GameCleanup or {}
table.insert(_G.GameCleanup, CleanupRoutine)
```

---

## 📊 Technical Architecture

### **File Structure**

```
MiracleHub-SteaLEgg/
├── core.lua          # Config, data structures, registry
├── logic.lua         # Automation, trust system, helpers
├── pages.lua         # UI components, widgets, buttons
└── README.md         # Documentation (this file)
```

### **Load Chain**

```
User Inject (Universal Loader)
       ↓
[Key Verification] → [PlaceId Detection]
       ↓
Fetch from: https://raw.githubusercontent.com/miracleverytime/MiracleHub-SteaLEgg/main/
       ↓
core.lua → Pages UI Framework → ultralow.lua → logic.lua → pages.lua → bootstrap.lua
       ↓
Menu Rendered & Ready
```

### **Trust System Flow**

```
Game Start → Idle 5 sec → Movement Samples Collected
                                         ↓
                    ┌────────────────────┴────────────────────┐
                    ↓                                         ↓
            Trust Score < 50%                           Trust Score ≥ 80%
                    ↓                                         ↓
           Limited Features                          Full Automation Enabled
           Slow Movement Only                       Stealth Mode Active
```

---

## 🔄 Updates & Changelog

### **[v5.0.0]** - Initial Release
- ✅ Trust system implementation with behavioral analysis
- ✅ Anti-cheat evasion (smooth movement, stealth mode)
- ✅ Auto egg collection with proximity detection
- ✅ Auto NPC combat automation
- ✅ Guard Tutorial awareness
- ✅ Emergency disable system
- ✅ Mobile platform support

---

## 🤝 Contributing

Contributions welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

---

## ⚠️ Disclaimer

**This tool is for educational purposes only.** 

- Use at your own risk
- Not affiliated with or endorsed by Roblox Corporation
- May violate Roblox Terms of Service
- Author not responsible for any account bans or consequences

**Intended Use:** Development, testing, and learning Roblox exploitation concepts.

---

## 📞 Support & Issues

- **GitHub Issues:** Report bugs or request features
- **Pull Requests:** Contribute improvements
- **Discord:** Join community server (link pending)

---

## 📜 License

MIT License - see LICENSE file for details

---

Made with ❤️ by MiracleHub Team
