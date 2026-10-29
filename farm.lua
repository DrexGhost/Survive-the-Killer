local Core, GUI = ...
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function build()
    local tab = GUI.makeTab("Farm", 4, "combat")
    local page = GUI.makePage()

    GUI.makeSectionHeader(page, "Auto Farm", 1)

    local farmHadNoclip = false
    local bodyVel = nil

    GUI.makeToggle(page, "Auto Farm (Garbage)", "Авто фарм мусора", Core.settings.autoFarmGarbage, 2, function(v)
        Core.settings.autoFarmGarbage = v
        if v then
            farmHadNoclip = Core.settings.noclip
            if not farmHadNoclip then
                Core.setNoclip(true)
                Core.NoclipActive = true
            end
        else
            if bodyVel then bodyVel:Destroy(); bodyVel = nil end
            if not farmHadNoclip then
                Core.setNoclip(false)
                Core.NoclipActive = false
            end
        end
    end, "autoFarmGarbage")

    GUI.makeSlider(page, "Farm Speed", 16, 500, Core.settings.farmSpeed or 100, 3, function(v)
        Core.settings.farmSpeed = v
    end, "farmSpeed")

    GUI.makeToggle(page, "Ignore Murder", "Не лететь к мусору рядом с убийцей", Core.settings.ignoreMurder, 4, function(v)
        Core.settings.ignoreMurder = v
    end, "ignoreMurder")

    GUI.makeSlider(page, "Ignore Radius", 1, 100, Core.settings.ignoreMurderRadius or 10, 5, function(v)
        Core.settings.ignoreMurderRadius = v
    end, "ignoreMurderRadius")

    local function getKillerPositions()
        local positions = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                if Core.getRole(p) == "Killer" then
                    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        table.insert(positions, hrp.Position)
                    end
                end
            end
        end
        return positions
    end

    local function lineHitsCircle(a, b, center, radius)
        local ab = b - a
        local abLenSq = ab:Dot(ab)
        if abLenSq < 0.0001 then return false end
        local ac = center - a
        local t = ac:Dot(ab) / abLenSq
        if t <= 0 or t >= 1 then return false end
        local proj = a + ab * t
        return (proj - center).Magnitude < radius
    end

    local function computeDirection(hrpPos, targetPos, killerPositions, radius)
        local toTarget = targetPos - hrpPos
        if toTarget.Magnitude < 0.01 then return Vector3.zero end
        local dirToTarget = toTarget.Unit

        if not killerPositions or #killerPositions == 0 then
            return dirToTarget
        end

        for _, kPos in ipairs(killerPositions) do
            local distToKiller = (hrpPos - kPos).Magnitude
            if distToKiller < radius then
                local away = hrpPos - kPos
                if away.Magnitude < 0.01 then
                    away = Vector3.new(0, 0, 1)
                end
                return away.Unit
            end
        end

        for _, kPos in ipairs(killerPositions) do
            if lineHitsCircle(hrpPos, targetPos, kPos, radius) then
                local toKiller = kPos - hrpPos
                local perp = Vector3.new(-toKiller.Z, 0, toKiller.X)
                if perp.Magnitude < 0.01 then
                    perp = Vector3.new(1, 0, 0)
                else
                    perp = perp.Unit
                end
                if perp:Dot(dirToTarget) < 0 then
                    perp = -perp
                end
                local detour = kPos + perp * (radius + 5)
                local newDir = detour - hrpPos
                if newDir.Magnitude > 0.01 then
                    return newDir.Unit
                end
            end
        end

        return dirToTarget
    end

    RunService.Stepped:Connect(function()
        if not Core.settings.autoFarmGarbage then return end

        Core.syncCharacter()

        if not Core.HRP or not Core.HRP.Parent then return end

        Core.enforceNoclip()

        if not bodyVel or not bodyVel.Parent or bodyVel.Parent ~= Core.HRP then
            if bodyVel then bodyVel:Destroy() end
            bodyVel = Instance.new("BodyVelocity")
            bodyVel.Name = "NexusXAutoFarm"
            bodyVel.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bodyVel.Velocity = Vector3.zero
            bodyVel.Parent = Core.HRP
        end

        local killerPositions = nil
        if Core.settings.ignoreMurder then
            killerPositions = getKillerPositions()
        end
        local ignoreRadius = Core.settings.ignoreMurderRadius or 10
        local speed = Core.settings.farmSpeed or 100

        local items = Core.getLootItems()
        local hrpPos = Core.HRP.Position
        local nearestPos, nearestDist = nil, math.huge

        for _, item in ipairs(items) do
            if item and item.Parent then
                local pos
                if item:IsA("BasePart") then
                    pos = item.Position
                elseif item:IsA("Model") then
                    local ok, p = pcall(function() return item:GetPivot().Position end)
                    if ok then pos = p end
                end
                if pos then
                    local skip = false
                    if killerPositions then
                        for _, kPos in ipairs(killerPositions) do
                            if (pos - kPos).Magnitude <= ignoreRadius then
                                skip = true
                                break
                            end
                        end
                    end
                    if not skip then
                        local d = (pos - hrpPos).Magnitude
                        if d < nearestDist then
                            nearestPos, nearestDist = pos, d
                        end
                    end
                end
            end
        end

        if not nearestPos then
            if killerPositions and #killerPositions > 0 then
                local escapeDir = nil
                for _, kPos in ipairs(killerPositions) do
                    if (hrpPos - kPos).Magnitude < ignoreRadius then
                        local away = hrpPos - kPos
                        if away.Magnitude < 0.01 then away = Vector3.new(0, 0, 1) end
                        escapeDir = away.Unit
                        break
                    end
                end
                if escapeDir then
                    bodyVel.Velocity = escapeDir * speed
                    return
                end
            end
            bodyVel.Velocity = Vector3.zero
            return
        end

        if nearestDist < 5 then
            bodyVel.Velocity = Vector3.zero
            Core.HRP.CFrame = CFrame.new(nearestPos)
            Core.HRP.AssemblyLinearVelocity = Vector3.zero
            return
        end

        local dir = computeDirection(hrpPos, nearestPos, killerPositions, ignoreRadius)
        bodyVel.Velocity = dir * speed
    end)

    tab.Button.MouseButton1Click:Connect(function() GUI.switchTab(tab, page) end)
    return tab, page
end
return build