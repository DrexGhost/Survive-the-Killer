local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local Core = {}

Core.CONFIG_FOLDER = "SurvivedTheKilledConfig"

Core.T = {
    bg1 = Color3.fromRGB(14, 18, 32),
    bg2 = Color3.fromRGB(6, 9, 18),
    panel = Color3.fromRGB(20, 26, 44),
    panelHi = Color3.fromRGB(30, 38, 62),
    card = Color3.fromRGB(24, 30, 50),
    cardHover = Color3.fromRGB(34, 42, 68),
    row = Color3.fromRGB(26, 32, 52),
    accent = Color3.fromRGB(0, 229, 204),
    accentDim = Color3.fromRGB(0, 140, 128),
    accentSoft = Color3.fromRGB(140, 250, 235),
    text = Color3.fromRGB(232, 238, 248),
    textDim = Color3.fromRGB(150, 162, 190),
    textMuted = Color3.fromRGB(90, 102, 130),
    stroke = Color3.fromRGB(44, 54, 86),
    success = Color3.fromRGB(80, 230, 140),
    warn = Color3.fromRGB(255, 200, 80),
    danger = Color3.fromRGB(255, 90, 110),
    toggleOff = Color3.fromRGB(48, 58, 88),
    white = Color3.fromRGB(255, 255, 255),
    red = Color3.fromRGB(255, 60, 60),
    green = Color3.fromRGB(60, 230, 90),
    blue = Color3.fromRGB(70, 130, 220),
    blueHi = Color3.fromRGB(90, 150, 240),
}

Core.settings = {
    menuOpen = true,
    antiAfk = true,
    watermark = false,
    watermarkScale = 100,
    guiScale = 85,
    floatBtnSize = 58,
    floatBtnPos = {0, 20, 0.5, 0},
    noclip = false,
    speed = false,
    walkSpeed = 50,
    espPlayers = false,
    espInnocent = false,
    espKiller = false,
    espItems = false,
    espExits = false,
    espTraps = false,
    autoFarmGarbage = false,
    farmSpeed = 100,
    ignoreMurder = false,
    ignoreMurderRadius = 10,
    killAllPlayers = false,
    safeDowned = false,
}

Core.toggleRefs = {}
Core.sliderRefs = {}
Core.SavedCollide = {}
Core.NoclipActive = false
Core.Char, Core.HRP, Core.Hum = nil, nil, nil
Core.remotes = {}
Core.itemPatterns = {"coin", "gem", "chest", "crate", "knife", "item", "loot", "pickup", "drop", "candy"}
Core._roleCache = {}
Core._charParts = nil
Core.cachedTraps = {}

function Core.bindCharacter(c)
    Core.Char = c
    Core.HRP = c:WaitForChild("HumanoidRootPart")
    Core.Hum = c:WaitForChild("Humanoid")
    Core.SavedCollide = {}
    Core.NoclipActive = false
    Core._charParts = nil
    if Core.settings and Core.settings.noclip then
        task.defer(Core.enforceNoclip)
    end
end

function Core.syncCharacter()
    local char = LocalPlayer.Character
    if not char then return end
    if Core.Char ~= char then
        Core.Char = char
        Core.HRP = char:FindFirstChild("HumanoidRootPart")
        Core.Hum = char:FindFirstChild("Humanoid")
        Core.SavedCollide = {}
        Core.NoclipActive = false
        Core._charParts = nil
    elseif not Core.HRP or not Core.HRP.Parent then
        Core.HRP = char:FindFirstChild("HumanoidRootPart")
        Core.Hum = char:FindFirstChild("Humanoid")
    end
end

if LocalPlayer.Character then Core.bindCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(Core.bindCharacter)

function Core.setNoclip(enabled)
    if not Core.Char then return end
    if enabled then
        for _, p in ipairs(Core.Char:GetDescendants()) do
            if p:IsA("BasePart") then
                if Core.SavedCollide[p] == nil then Core.SavedCollide[p] = p.CanCollide end
                p.CanCollide = false
            end
        end
    else
        for part, state in pairs(Core.SavedCollide) do
            if part and part.Parent then part.CanCollide = state end
        end
        Core.SavedCollide = {}
    end
end

function Core._rebuildCharParts()
    Core._charParts = {}
    if not Core.Char or not Core.Char.Parent then return end
    for _, p in ipairs(Core.Char:GetDescendants()) do
        if p:IsA("BasePart") then
            table.insert(Core._charParts, p)
            if Core.SavedCollide[p] == nil then Core.SavedCollide[p] = p.CanCollide end
        end
    end
end

function Core.enforceNoclip()
    if not Core.Char or not Core.Char.Parent then return end
    if not Core._charParts then Core._rebuildCharParts() end
    local parts = Core._charParts
    for i = 1, #parts do
        local p = parts[i]
        if p.Parent and p.CanCollide then
            if Core.SavedCollide[p] == nil then Core.SavedCollide[p] = p.CanCollide end
            p.CanCollide = false
        end
    end
end

function Core.saveSetting(name, value)
    Core.settings[name] = value
    if not Core.dataStore then return end
    local stored = Core.dataStore:FindFirstChild(name)
    local dType
    if type(value) == "table" then dType = "table"
    elseif type(value) == "string" then dType = "string"
    elseif type(value) == "number" then dType = "number"
    elseif type(value) == "boolean" then dType = "bool"
    else return end
    if stored and stored:GetAttribute("dataType") ~= dType then
        stored:Destroy()
        stored = nil
    end
    if not stored then
        if dType == "table" or dType == "string" then stored = Instance.new("StringValue")
        elseif dType == "number" then stored = Instance.new("NumberValue")
        else stored = Instance.new("BoolValue") end
        stored:SetAttribute("dataType", dType)
        stored.Name = name
        stored.Parent = Core.dataStore
    end
    if dType == "table" then stored.Value = HttpService:JSONEncode(value)
    else stored.Value = value end
end

function Core.loadSettings()
    local ok, result = pcall(function()
        if not LocalPlayer:FindFirstChild("NexusXSettings") then
            local ds = Instance.new("Folder")
            ds.Name = "NexusXSettings"
            ds.Parent = LocalPlayer
        end
        return LocalPlayer.NexusXSettings
    end)
    if ok and result then
        Core.dataStore = result
        for name, defaultValue in pairs(Core.settings) do
            local stored = Core.dataStore:FindFirstChild(name)
            if stored then
                local dt = stored:GetAttribute("dataType")
                if dt == "table" and stored:IsA("StringValue") then
                    local sOk, decoded = pcall(function() return HttpService:JSONDecode(stored.Value) end)
                    if sOk and type(decoded) == "table" then Core.settings[name] = decoded end
                elseif type(defaultValue) == type(stored.Value) then
                    Core.settings[name] = stored.Value
                end
            else
                Core.saveSetting(name, defaultValue)
            end
        end
    end
end

function Core.listConfigs()
    if not isfolder or not listfiles then return {} end
    pcall(function() if not isfolder(Core.CONFIG_FOLDER) then makefolder(Core.CONFIG_FOLDER) end end)
    local result = {}
    local ok, files = pcall(function() return listfiles(Core.CONFIG_FOLDER) end)
    if not ok or type(files) ~= "table" then return result end
    for _, filePath in ipairs(files) do
        local n = tostring(filePath):match("([^/\\]+)%.json$")
        if n then table.insert(result, n) end
    end
    table.sort(result)
    return result
end

function Core.saveConfigAs(name)
    local data = {}
    for k, v in pairs(Core.settings) do data[k] = v end
    local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok then return false end
    return pcall(function() writefile(Core.CONFIG_FOLDER .. "/" .. name .. ".json", encoded) end)
end

function Core.loadConfigFrom(name)
    local path = Core.CONFIG_FOLDER .. "/" .. name .. ".json"
    if not isfile or not isfile(path) then return false end
    local ok, contents = pcall(function() return readfile(path) end)
    if not ok then return false end
    local ok2, decoded = pcall(function() return HttpService:JSONDecode(contents) end)
    if not ok2 or type(decoded) ~= "table" then return false end
    for k, v in pairs(decoded) do
        if Core.settings[k] ~= nil and type(Core.settings[k]) == type(v) then
            Core.settings[k] = v
            Core.saveSetting(k, v)
        end
    end
    return true
end

function Core.deleteConfig(name)
    return pcall(function() delfile(Core.CONFIG_FOLDER .. "/" .. name .. ".json") end)
end

function Core.getRole(player)
    if not player then return "Innocent" end
    local ok, team = pcall(function() return player.Team end)
    if ok and team and team.Name then
        local n = string.lower(team.Name)
        if string.find(n, "killer", 1, true) or string.find(n, "murder", 1, true) then return "Killer" end
        if string.find(n, "survivor", 1, true) or string.find(n, "innocent", 1, true) then return "Innocent" end
    end
    local role = player:GetAttribute("Role") or player:GetAttribute("role")
    if typeof(role) == "string" then
        local n = string.lower(role)
        if string.find(n, "killer", 1, true) or string.find(n, "murder", 1, true) then return "Killer" end
    end
    if player:GetAttribute("IsKiller") == true or player:GetAttribute("isKiller") == true then return "Killer" end
    if player.Character then
        local ca = player.Character:GetAttribute("Role")
        if typeof(ca) == "string" and (string.find(string.lower(ca), "killer", 1, true) or string.find(string.lower(ca), "murder", 1, true)) then return "Killer" end
        if player.Character:GetAttribute("IsKiller") == true or player.Character:GetAttribute("isKiller") == true then return "Killer" end
    end
    return "Innocent"
end

function Core.getRoleCached(player)
    if not player then return "Innocent" end
    local now = os.clock()
    local c = Core._roleCache[player]
    if c and now - c.t < 1.0 then return c.v end
    local v = Core.getRole(player)
    Core._roleCache[player] = { v = v, t = now }
    return v
end

function Core.findRemote(pattern)
    if not pattern then return nil end
    local lp = string.lower(pattern)
    for _, d in ipairs(RS:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
            if string.find(string.lower(d.Name), lp, 1, true) then return d end
        end
    end
    return nil
end

function Core.isLootVisible(spot)
    if not spot or not spot.Parent then return false end
    for _, c in ipairs(spot:GetDescendants()) do
        if c:IsA("BasePart") or c:IsA("Decal") or c:IsA("Texture") then
            local ok, t = pcall(function() return c.Transparency end)
            if ok and type(t) == "number" and t < 1 then return true end
        elseif c:IsA("ParticleEmitter") or c:IsA("Beam") or c:IsA("Trail") then
            local ok, e = pcall(function() return c.Enabled end)
            if ok and e == true then return true end
        elseif c:IsA("BillboardGui") or c:IsA("SurfaceGui") then
            local okE, e = pcall(function() return c.Enabled end)
            local okV, v = pcall(function() return c.Visible end)
            if okE and e ~= false and okV and v ~= false then return true end
        end
    end
    return false
end

function Core.isItem(obj)
    if not obj then return false end
    local ok, hasTag = pcall(function() return obj:HasTag("LootSpawn") end)
    if ok and hasTag then
        local okLoot, loot = pcall(function() return obj:GetAttribute("Loot") end)
        if okLoot and typeof(loot) == "string" and loot == "" then return false end
        return Core.isLootVisible(obj)
    end
    local okLoot, loot = pcall(function() return obj:GetAttribute("Loot") end)
    if okLoot and typeof(loot) == "string" and loot ~= "" then
        return Core.isLootVisible(obj)
    end
    if obj.Parent and typeof(obj.Parent.Name) == "string" and string.find(string.lower(obj.Parent.Name), "lootspawn", 1, true) then
        return Core.isLootVisible(obj)
    end
    local n = string.lower(obj.Name)
    for _, pat in ipairs(Core.itemPatterns) do
        if string.find(n, pat, 1, true) then return true end
    end
    return false
end

function Core.getLootItems()
    local list = {}
    local seen = {}

    local function push(obj)
        if not obj or not obj.Parent or seen[obj] then return end
        if not Core.isItem(obj) then return end
        seen[obj] = true
        table.insert(list, obj)
    end

    local ok, tagged = pcall(function() return CollectionService:GetTagged("LootSpawn") end)
    if ok and type(tagged) == "table" then
        for _, obj in ipairs(tagged) do push(obj) end
    end

    local function scanFolder(folder)
        for _, child in ipairs(folder:GetChildren()) do
            if not seen[child] and (child:IsA("BasePart") or child:IsA("Model")) then
                if Core.isItem(child) then
                    seen[child] = true
                    table.insert(list, child)
                end
            end
        end
    end

    for _, top in ipairs(workspace:GetChildren()) do
        if top:IsA("Folder") and string.find(string.lower(top.Name), "lootspawn", 1, true) then
            scanFolder(top)
        elseif top:IsA("Model") or top:IsA("Folder") then
            for _, sub in ipairs(top:GetChildren()) do
                if sub:IsA("Folder") and string.find(string.lower(sub.Name), "lootspawn", 1, true) then
                    scanFolder(sub)
                end
            end
        end
    end

    return list
end

function Core.isTrapModel(obj)
    if not obj or not obj.Parent then return false end
    if not obj:IsA("Model") then return false end
    if obj.Name == "Trap" or obj.Name == "BearTrap" or obj.Name == "SnapTrap" then return true end
    local hb = obj:FindFirstChild("HitBox")
    if hb and hb:IsA("BasePart") then return true end
    return false
end

function Core.getTrapPositions()
    local list = {}
    local seen = {}
    for _, top in ipairs(workspace:GetChildren()) do
        if Core.isTrapModel(top) and not seen[top] then
            seen[top] = true
            local hb = top:FindFirstChild("HitBox")
            local pos
            if hb and hb:IsA("BasePart") then pos = hb.Position end
            if not pos then
                local ok, p = pcall(function() return top:GetPivot().Position end)
                if ok then pos = p end
            end
            if pos then table.insert(list, pos) end
        end
        if top:IsA("Model") or top:IsA("Folder") then
            for _, sub in ipairs(top:GetChildren()) do
                if Core.isTrapModel(sub) and not seen[sub] then
                    seen[sub] = true
                    local hb = sub:FindFirstChild("HitBox")
                    local pos
                    if hb and hb:IsA("BasePart") then pos = hb.Position end
                    if not pos then
                        local ok, p = pcall(function() return sub:GetPivot().Position end)
                        if ok then pos = p end
                    end
                    if pos then table.insert(list, pos) end
                end
            end
        end
    end
    return list
end

task.spawn(function()
    while task.wait(60) do
        if Core.settings.antiAfk then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end
    end
end)

task.spawn(function()
    while task.wait(1) do
        Core.cachedTraps = Core.getTrapPositions()
    end
end)

task.spawn(function()
    while task.wait(0.05) do
        if Core.HRP and Core.HRP.Parent then
            local hrpPos = Core.HRP.Position
            local trapped = false
            for _, tPos in ipairs(Core.cachedTraps) do
                local dx = hrpPos.X - tPos.X
                local dz = hrpPos.Z - tPos.Z
                if math.sqrt(dx*dx + dz*dz) < 5 then
                    trapped = true
                    break
                end
            end
            if trapped then
                pcall(function()
                    local vp = workspace.CurrentCamera.ViewportSize
                    local cx = math.floor(vp.X / 2)
                    local cy = math.floor(vp.Y / 2)
                    VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
                    VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
                end)
            end
        end
    end
end)

Core.loadSettings()
if Core.settings.antiAfk == nil then Core.settings.antiAfk = true end
Core.saveSetting("antiAfk", Core.settings.antiAfk)

return Core