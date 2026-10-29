local Core, GUI, ESPDisplay = ...
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local function build()
    local tab = GUI.makeTab("ESP", 3, "combat")
    local page = GUI.makePage()
    local T = Core.T

    GUI.makeSectionHeader(page, "Players", 1)

    GUI.makeToggle(page, "Esp Player", "Видеть игроков сквозь стены", Core.settings.espPlayers, 2, function(v)
        Core.settings.espPlayers = v
        if not v then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    ESPDisplay.remove(p.Character)
                end
            end
        end
    end, "espPlayers")

    GUI.makeToggle(page, "Esp Innocent", "Показывать обычных игроков", Core.settings.espInnocent, 3, function(v)
        Core.settings.espInnocent = v
        if not v then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and Core.getRoleCached(p) == "Innocent" then
                    ESPDisplay.remove(p.Character)
                end
            end
        end
    end, "espInnocent")

    GUI.makeToggle(page, "Esp Killer", "Показывает убийцу", Core.settings.espKiller, 4, function(v)
        Core.settings.espKiller = v
        if not v then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and Core.getRoleCached(p) == "Killer" then
                    ESPDisplay.remove(p.Character)
                end
            end
        end
    end, "espKiller")

    GUI.makeSectionHeader(page, "Other", 5)

    GUI.makeToggle(page, "Esp Items", "Показывать Мусор (предметы)", Core.settings.espItems, 6, function(v)
        Core.settings.espItems = v
    end, "espItems")

    local trackedExits = {}
    local lastExitScan = 0

    local function readBool(v)
        if typeof(v) == "boolean" then return v end
        if typeof(v) == "string" then
            local l = string.lower(v)
            if l == "true" or l == "open" or l == "opened" or l == "unlocked" then return true end
            if l == "false" or l == "closed" or l == "locked" then return false end
        end
        if typeof(v) == "number" then return v ~= 0 end
        return nil
    end

    local function checkExitObj(exitObj)
        local attrs = {"Open", "IsOpen", "Opened", "Unlocked", "Locked", "State", "Status"}
        for _, a in ipairs(attrs) do
            local ok, val = pcall(function() return exitObj:GetAttribute(a) end)
            if ok and val ~= nil then
                if a == "Locked" then
                    local b = readBool(val)
                    if b ~= nil then return not b end
                else
                    local b = readBool(val)
                    if b ~= nil then return b end
                end
            end
        end
        for _, c in ipairs(exitObj:GetChildren()) do
            local n = string.lower(c.Name)
            if n == "glow" or n == "openglow" or n == "teleport" or n == "portal" then
                if c:IsA("BasePart") and c.Transparency < 1 then return true end
                if c:IsA("ParticleEmitter") and c.Enabled then return true end
                if c:IsA("PointLight") and c.Enabled then return true end
                if c:IsA("SurfaceGui") and c.Enabled then return true end
                return true
            end
        end
        for _, c in ipairs(exitObj:GetChildren()) do
            if c:IsA("BasePart") and c.Transparency < 1 then return true end
        end
        return nil
    end

    local function getExitsOpen(exitObj)
        local sources = {
            {obj = ReplicatedStorage:FindFirstChild("MatchInfo") and ReplicatedStorage.MatchInfo:FindFirstChild("ExitsOpen")},
            {obj = ReplicatedStorage:FindFirstChild("ExitsOpen")},
            {obj = workspace:FindFirstChild("ExitsOpen")},
        }
        local cm = workspace:FindFirstChild("CurrentMap")
        if cm then
            table.insert(sources, {obj = cm:FindFirstChild("ExitsOpen")})
        end

        for _, s in ipairs(sources) do
            if s.obj then
                local ok, v = pcall(function() return s.obj.Value end)
                if ok then
                    local b = readBool(v)
                    if b ~= nil then return b end
                end
            end
        end

        if exitObj then
            local b = checkExitObj(exitObj)
            if b ~= nil then return b end
        end

        return nil
    end

    local function isExit(obj)
        if not obj or not obj.Parent then return false end
        if not (obj:IsA("BasePart") or obj:IsA("Model")) then return false end
        local n = obj.Name
        if n == "ExitDoor" or n == "Exit" or n == "EscapeDoor" or n == "Escape" then return true end
        if string.find(n, "Exit", 1, true) and not string.find(n, "ExitSign", 1, true) then return true end
        local okA, isExitAttr = pcall(function() return obj:GetAttribute("IsExit") end)
        if okA and isExitAttr == true then return true end
        local okT1, hasTag1 = pcall(function() return obj:HasTag("ExitDoor") end)
        if okT1 and hasTag1 then return true end
        local okT2, hasTag2 = pcall(function() return obj:HasTag("Exit") end)
        if okT2 and hasTag2 then return true end
        return false
    end

    local function hasExitAncestor(obj)
        local p = obj.Parent
        while p and p ~= workspace do
            if isExit(p) then return true end
            p = p.Parent
        end
        return false
    end

    local function scanExits()
        local found = {}
        for _, obj in ipairs(workspace:GetDescendants()) do
            if isExit(obj) and not hasExitAncestor(obj) then
                found[obj] = true
            end
        end
        return found
    end

    local function computeUnifiedState(found)
        local anyTrue = false
        local anyFalse = false
        for obj in pairs(found) do
            local isOpen = getExitsOpen(obj)
            if isOpen == true then
                anyTrue = true
                break
            elseif isOpen == false then
                anyFalse = true
            end
        end
        if anyTrue then return true end
        if anyFalse then return false end
        return nil
    end

    local function applyExits()
        local found = scanExits()
        local isOpen = computeUnifiedState(found)

        local color, label
        if isOpen == true then
            color = T.green
            label = "EXIT (OPEN)"
        elseif isOpen == false then
            color = T.red
            label = "EXIT (CLOSED)"
        else
            color = T.warn
            label = "EXIT (?)"
        end

        for obj in pairs(found) do
            ESPDisplay.add(obj, {
                color = color,
                name = label,
                distance = true,
                fillTransparency = 0.4,
                outlineTransparency = 0,
            })
        end

        for obj in pairs(trackedExits) do
            if not found[obj] or not obj.Parent then
                ESPDisplay.remove(obj)
            end
        end

        trackedExits = found
    end

    GUI.makeToggle(page, "Esp Exit", "Подсвечивать выходы (зелёный - открыт, красный - закрыт)", Core.settings.espExits, 7, function(v)
        Core.settings.espExits = v
        if not v then
            for obj in pairs(trackedExits) do
                ESPDisplay.remove(obj)
            end
            trackedExits = {}
        else
            applyExits()
        end
    end, "espExits")

    local lastUpdate = 0
    local lastItemsScan = 0
    local lastItemCheck = 0
    local trackedItems = {}

    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        if now - lastUpdate < 0.2 then return end
        lastUpdate = now

        ESPDisplay.update()

        if Core.settings.espPlayers then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    local role = Core.getRoleCached(p)
                    if role == "Killer" and Core.settings.espKiller then
                        ESPDisplay.add(p.Character, {color = T.red, name = p.Name, fillTransparency = 0.55, outlineTransparency = 0})
                    elseif role == "Innocent" and Core.settings.espInnocent then
                        ESPDisplay.add(p.Character, {color = T.white, name = p.Name, fillTransparency = 0.55, outlineTransparency = 0})
                    else
                        ESPDisplay.remove(p.Character)
                    end
                end
            end
        end

        if now - lastItemsScan >= 1 then
            lastItemsScan = now
            if Core.settings.espItems then
                local seen = {}
                for _, obj in ipairs(Core.getLootItems()) do
                    if obj and obj.Parent then
                        seen[obj] = true
                        ESPDisplay.add(obj, {
                            color = T.green,
                            distance = true,
                            fillTransparency = 0.25,
                            outlineTransparency = 0,
                            outlineColor = Color3.fromRGB(0, 255, 80),
                            depthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                        })
                    end
                end
                for obj in pairs(trackedItems) do
                    if not seen[obj] then
                        ESPDisplay.remove(obj)
                    end
                end
                trackedItems = seen
            else
                for obj in pairs(trackedItems) do
                    ESPDisplay.remove(obj)
                end
                trackedItems = {}
            end
        end

        if Core.settings.espItems and now - lastItemCheck >= 0.1 then
            lastItemCheck = now
            for obj in pairs(trackedItems) do
                if not obj or not obj.Parent then
                    ESPDisplay.remove(obj)
                    trackedItems[obj] = nil
                else
                    local okLoot, loot = pcall(function() return obj:GetAttribute("Loot") end)
                    if okLoot and typeof(loot) == "string" and loot == "" then
                        ESPDisplay.remove(obj)
                        trackedItems[obj] = nil
                    elseif not Core.isLootVisible(obj) then
                        ESPDisplay.remove(obj)
                        trackedItems[obj] = nil
                    end
                end
            end
        end

        if Core.settings.espExits and now - lastExitScan >= 1 then
            lastExitScan = now
            applyExits()
        end
    end)

    tab.Button.MouseButton1Click:Connect(function() GUI.switchTab(tab, page) end)
    return tab, page
end
return build