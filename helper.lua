local Core, GUI = ...
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function build()
    local tab = GUI.makeTab("Helper", 2, "helper")
    local page = GUI.makePage()
    local T = Core.T

    GUI.makeSectionHeader(page, "Helper Killer", 1)

    local bodyVel = nil
    local helperHadNoclip = false
    local KILL_MAX_DISTANCE = 500
    local KILL_SPEED = 100
    local ATTACK_COOLDOWN = 0.3
    local TP_DISTANCE = 5
    local lastAttack = 0

    local function isPlayerDowned(player)
        if not player or not player.Character then return true end
        local char = player.Character
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return true end
        if hum.Health <= 0 then return true end

        for _, attrName in ipairs({"Downed", "IsDowned", "Down", "Crawling", "IsCrawling", "Knocked", "IsKnocked"}) do
            local v1 = char:GetAttribute(attrName)
            local v2 = player:GetAttribute(attrName)
            if v1 == true or v2 == true then return true end
        end

        if hum.PlatformStand == true then return true end

        local ok, state = pcall(function() return hum:GetState() end)
        if ok then
            if state == Enum.HumanoidStateType.Physics
                or state == Enum.HumanoidStateType.FallingDown
                or state == Enum.HumanoidStateType.Ragdoll then
                return true
            end
        end

        return false
    end

    local function getWeapon()
        if not Core.Char then return nil end
        local priority = {"Knife", "Slycer", "Slicer", "Weapon", "Blade"}
        local bp = LocalPlayer:FindFirstChild("Backpack")

        for _, name in ipairs(priority) do
            local t = Core.Char:FindFirstChild(name)
            if t and t:IsA("Tool") then return t end
        end

        if bp then
            for _, name in ipairs(priority) do
                local t = bp:FindFirstChild(name)
                if t and t:IsA("Tool") then
                    for _, c in ipairs(Core.Char:GetChildren()) do
                        if c:IsA("Tool") and c ~= t then c.Parent = bp end
                    end
                    t.Parent = Core.Char
                    return Core.Char:FindFirstChild(name)
                end
            end
        end

        local anyTool = Core.Char:FindFirstChildOfClass("Tool")
        if anyTool then return anyTool end

        return nil
    end

    local function getNearestTarget(hrpPos)
        local best, bestDist = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    if not isPlayerDowned(p) then
                        local d = (hrp.Position - hrpPos).Magnitude
                        if d <= KILL_MAX_DISTANCE and d < bestDist then
                            best = { player = p, hrp = hrp, pos = hrp.Position }
                            bestDist = d
                        end
                    end
                end
            end
        end
        return best, bestDist
    end

    local function tryAttack()
        local weapon = getWeapon()
        if weapon then
            pcall(function() weapon:Activate() end)
            return
        end

        local remote = Core.findRemote("attack")
            or Core.findRemote("hit")
            or Core.findRemote("slash")
            or Core.findRemote("kill")
            or Core.findRemote("stab")

        if remote then
            pcall(function()
                if remote:IsA("RemoteEvent") then
                    remote:FireServer()
                elseif remote:IsA("RemoteFunction") then
                    remote:InvokeServer()
                end
            end)
        end
    end

    GUI.makeToggle(page, "Kill all Player", "Убивать всех игроков", Core.settings.killAllPlayers, 2, function(v)
        Core.settings.killAllPlayers = v
        if v then
            helperHadNoclip = Core.settings.noclip
            if not helperHadNoclip then
                Core.setNoclip(true)
                Core.NoclipActive = true
            end
        else
            if bodyVel then bodyVel:Destroy(); bodyVel = nil end
            if not helperHadNoclip then
                Core.setNoclip(false)
                Core.NoclipActive = false
            end
            lastAttack = 0
        end
    end, "killAllPlayers")

    RunService.Stepped:Connect(function()
        if not Core.settings.killAllPlayers then return end

        Core.syncCharacter()

        if not Core.HRP or not Core.HRP.Parent then return end

        if Core.getRoleCached(LocalPlayer) ~= "Killer" then
            if bodyVel and bodyVel.Parent then
                bodyVel.Velocity = Vector3.zero
            end
            return
        end

        Core.enforceNoclip()

        if not bodyVel or not bodyVel.Parent or bodyVel.Parent ~= Core.HRP then
            if bodyVel then bodyVel:Destroy() end
            bodyVel = Instance.new("BodyVelocity")
            bodyVel.Name = "NexusXKillAll"
            bodyVel.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bodyVel.Velocity = Vector3.zero
            bodyVel.Parent = Core.HRP
        end

        local now = os.clock()
        local hrpPos = Core.HRP.Position
        local target, dist = getNearestTarget(hrpPos)

        if not target then
            bodyVel.Velocity = Vector3.zero
            return
        end

        if dist < TP_DISTANCE then
            bodyVel.Velocity = Vector3.zero
            Core.HRP.CFrame = CFrame.new(target.pos)
            Core.HRP.AssemblyLinearVelocity = Vector3.zero

            if now - lastAttack >= ATTACK_COOLDOWN then
                lastAttack = now
                tryAttack()
            end
        else
            local dx = target.pos.X - hrpPos.X
            local dz = target.pos.Z - hrpPos.Z
            local len = math.sqrt(dx * dx + dz * dz)
            if len > 0.01 then
                bodyVel.Velocity = Vector3.new(dx / len, 0, dz / len) * KILL_SPEED
            else
                bodyVel.Velocity = Vector3.zero
            end
        end
    end)

    tab.Button.MouseButton1Click:Connect(function() GUI.switchTab(tab, page) end)
    return tab, page
end
return build