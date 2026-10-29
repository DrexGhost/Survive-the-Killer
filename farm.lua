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
    local MAX_LOOT_DISTANCE = 500

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

    local function flatDist(a, b)
        local dx = a.X - b.X
        local dz = a.Z - b.Z
        return math.sqrt(dx * dx + dz * dz)
    end

    local function flatDir(from, to)
        local dx = to.X - from.X
        local dz = to.Z - from.Z
        local len = math.sqrt(dx * dx + dz * dz)
        if len < 0.01 then return Vector3.zero end
        return Vector3.new(dx / len, 0, dz / len)
    end

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
        local abx = b.X - a.X
        local abz = b.Z - a.Z
        local abLenSq = abx * abx + abz * abz
        if abLenSq < 0.0001 then return false end
        local acx = center.X - a.X
        local acz = center.Z - a.Z
        local t = (acx * abx + acz * abz) / abLenSq
        if t <= 0 or t >= 1 then return false end
        local projx = a.X + abx * t
        local projz = a.Z + abz * t
        local dx = projx - center.X
        local dz = projz - center.Z
        return math.sqrt(dx * dx + dz * dz) < radius
    end

    local detour = nil

    local function pickDetourSide(hrpPos, targetPos, kPos, radius)
        local toKX = kPos.X - hrpPos.X
        local toKZ = kPos.Z - hrpPos.Z
        local len = math.sqrt(toKX * toKX + toKZ * toKZ)
        if len < 0.01 then toKX, toKZ, len = 1, 0, 1 end
        toKX = toKX / len
        toKZ = toKZ / len

        local leftPX, leftPZ = -toKZ, toKX
        local rightPX, rightPZ = toKZ, -toKX

        local tX = targetPos.X - hrpPos.X
        local tZ = targetPos.Z - hrpPos.Z
        local tLen = math.sqrt(tX * tX + tZ * tZ)
        if tLen < 0.01 then tX, tZ, tLen = 0, 1, 1 end
        tX = tX / tLen
        tZ = tZ / tLen

        local leftDot = leftPX * tX + leftPZ * tZ
        local rightDot = rightPX * tX + rightPZ * tZ

        local perpX, perpZ
        if math.abs(leftDot) >= math.abs(rightDot) then
            perpX = leftDot >= 0 and leftPX or -leftPX
            perpZ = leftDot >= 0 and leftPZ or -leftPZ
        else
            perpX = rightDot >= 0 and rightPX or -rightPX
            perpZ = rightDot >= 0 and rightPZ or -rightPZ
        end

        return Vector3.new(kPos.X + perpX * (radius + 5), hrpPos.Y, kPos.Z + perpZ * (radius + 5))
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
            local distToDetour = flatDist(hrpPos, detour.target)
            local reached = distToDetour < 6
            local expired = now >= detour.expires

            local targetSafe = true
            local pathClear = true

            if not reached and not expired then
                for _, kPos in ipairs(killerPositions) do
                    if flatDist(detour.target, kPos) <= radius then
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
                    local d = (pos - hrpPos).Magnitude
                    if d <= MAX_LOOT_DISTANCE then
                        local skip = false
                        if killerPositions then
                            for _, kPos in ipairs(killerPositions) do
                                if flatDist(pos, kPos) <= ignoreRadius then
                                    skip = true
                                    break
                                end
                            end
                        end
                        if not skip and d < nearestDist then
                            nearestPos, nearestDist = pos, d
                        end
                    end
                end
            end
        end

        if not nearestPos then
            clearDetour()
            if killerPositions and #killerPositions > 0 then
                local escapeVec = nil
                for _, kPos in ipairs(killerPositions) do
                    if flatDist(hrpPos, kPos) < ignoreRadius then
                        escapeVec = flatDir(kPos, hrpPos)
                        break
                    end
                end
                if escapeVec and escapeVec.Magnitude > 0.01 then
                    bodyVel.Velocity = escapeVec * speed
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
                if flatDist(hrpPos, kPos) < ignoreRadius then
                    local escapeVec = flatDir(kPos, hrpPos)
                    if escapeVec.Magnitude > 0.01 then
                        bodyVel.Velocity = escapeVec * speed
                        return
                    end
                end
            end

            local detourPos = updateDetour(hrpPos, nearestPos, killerPositions, ignoreRadius, now)
            if detourPos then
                moveTarget = detourPos
            end
        else
            clearDetour()
        end

        local dir = flatDir(hrpPos, moveTarget)
        if dir.Magnitude < 0.01 then
            bodyVel.Velocity = Vector3.zero
            return
        end
        bodyVel.Velocity = dir * speed
    end)

    tab.Button.MouseButton1Click:Connect(function() GUI.switchTab(tab, page) end)
    return tab, page
end
return build