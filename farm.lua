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

    local detour = nil

    local function pickDetourSide(hrpPos, targetPos, kPos, radius)
        local toKiller = Vector3.new(kPos.X - hrpPos.X, 0, kPos.Z - hrpPos.Z)
        if toKiller.Magnitude < 0.01 then
            toKiller = Vector3.new(1, 0, 0)
        end
        toKiller = toKiller.Unit

        local leftPerp = Vector3.new(-toKiller.Z, 0, toKiller.X)
        local rightPerp = Vector3.new(toKiller.Z, 0, -toKiller.X)

        local targetFlat = Vector3.new(targetPos.X - hrpPos.X, 0, targetPos.Z - hrpPos.Z)
        if targetFlat.Magnitude < 0.01 then targetFlat = Vector3.new(0, 0, 1) end
        targetFlat = targetFlat.Unit

        local leftDot = leftPerp:Dot(targetFlat)
        local rightDot = rightPerp:Dot(targetFlat)

        local perp
        if math.abs(leftDot) >= math.abs(rightDot) then
            perp = leftDot >= 0 and leftPerp or -leftPerp
        else
            perp = rightDot >= 0 and rightPerp or -rightPerp
        end

        return Vector3.new(kPos.X + perp.X * (radius + 5), kPos.Y, kPos.Z + perp.Z * (radius + 5))
    end

    local function clearDetour()
        detour = nil
    end

    local function updateDetour(hrpPos, targetPos, killerPositions, radius, now)
        if not killerPositions or #killerPositions == 0 then
            clearDetour()
            return nil
        end

        local blockingKiller = nil
        for _, kPos in ipairs(killerPositions) do
            if lineHitsCircle(hrpPos, targetPos, kPos, radius) then
                blockingKiller = kPos
                break
            end
        end

        if not blockingKiller then
            clearDetour()
            return nil
        end

        if detour then
            local distToDetour = (hrpPos - detour.target).Magnitude
            local reached = distToDetour < 6
            local expired = now >= detour.expires

            local targetSafe = true
            local pathClear = true

            if not reached and not expired then
                for _, kPos in ipairs(killerPositions) do
                    if (detour.target - kPos).Magnitude <= radius then
                        targetSafe = false
                        break
                    end
                end

                if targetSafe then
                    for _, kPos in ipairs(killerPositions) do
                        if lineHitsCircle(hrpPos, detour.target, kPos, radius) then
                            pathClear = false
                            break
                        end
                    end
                end
            end

            if targetSafe and pathClear and not reached and not expired then
                return detour.target
            end
        end

        local newTarget = pickDetourSide(hrpPos, targetPos, blockingKiller, radius)
        detour = {
            target = newTarget,
            expires = now + 2.0,
        }
        return newTarget
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
        local now = os.clock()

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
            clearDetour()
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

        local moveTarget = nearestPos

        if killerPositions and #killerPositions > 0 then
            for _, kPos in ipairs(killerPositions) do
                if (hrpPos - kPos).Magnitude < ignoreRadius then
                    local away = hrpPos - kPos
                    if away.Magnitude < 0.01 then away = Vector3.new(0, 0, 1) end
                    bodyVel.Velocity = away.Unit * speed
                    return
                end
            end

            local detourPos = updateDetour(hrpPos, nearestPos, killerPositions, ignoreRadius, now)
            if detourPos then
                moveTarget = detourPos
            end
        else
            clearDetour()
        end

        local toTarget = moveTarget - hrpPos
        if toTarget.Magnitude < 0.01 then
            bodyVel.Velocity = Vector3.zero
            return
        end
        bodyVel.Velocity = toTarget.Unit * speed
    end)

    tab.Button.MouseButton1Click:Connect(function() GUI.switchTab(tab, page) end)
    return tab, page
end
return build