local Core, GUI = ...
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local function build()
    local tab = GUI.makeTab("Farm", 4, "combat")
    local page = GUI.makePage()

    GUI.makeSectionHeader(page, "Auto Farm", 1)

    local farmHadNoclip = false
    local bodyVel = nil
    local MAX_LOOT_DISTANCE = 500
    local MAX_EXIT_DISTANCE = 500

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
                if Core.getRoleCached(p) == "Killer" then
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

    local function pickSideDir(hrpPos, targetPos, kPos)
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

        return Vector3.new(perpX, 0, perpZ)
    end

    local detour = nil

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

            if not reached and not expired then
                local targetSafe = true
                for _, kPos in ipairs(killerPositions) do
                    if flatDist(detour.target, kPos) <= radius then
                        targetSafe = false
                        break
                    end
                end
                if targetSafe then
                    return detour.target
                end
            elseif expired then
                clearDetour()
            end
        end

        local side = detour and detour.side
        if not side then
            side = pickSideDir(hrpPos, targetPos, blockingKiller)
        end

        local offset = radius + 10
        local newTarget = Vector3.new(
            blockingKiller.X + side.X * offset,
            hrpPos.Y,
            blockingKiller.Z + side.Z * offset
        )

        detour = {
            target = newTarget,
            side = side,
            expires = now + 3.0,
        }

        return newTarget
    end

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

    local function getExitPositions()
        local list = {}
        for _, obj in ipairs(workspace:GetDescendants()) do
            if isExit(obj) and not hasExitAncestor(obj) then
                local pos
                if obj:IsA("BasePart") then
                    pos = obj.Position
                elseif obj:IsA("Model") then
                    local ok, p = pcall(function() return obj:GetPivot().Position end)
                    if ok then pos = p end
                end
                if pos then
                    table.insert(list, pos)
                end
            end
        end
        return list
    end

    local function exitsAreOpen()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if isExit(obj) and not hasExitAncestor(obj) then
                local isOpen = getExitsOpen(obj)
                if isOpen == true then return true end
            end
        end
        return false
    end

    local cacheKillers = {}
    local cacheExits = {}
    local cacheExitsOpen = false
    local lastCache = 0

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

        local now = os.clock()

        if now - lastCache >= 1 then
            lastCache = now
            cacheKillers = getKillerPositions()
            cacheExitsOpen = exitsAreOpen()
            cacheExits = cacheExitsOpen and getExitPositions() or {}
        end

        local killerPositions = cacheKillers
        local ignoreRadius = Core.settings.ignoreMurderRadius or 10
        local speed = Core.settings.farmSpeed or 100

        local hrpPos = Core.HRP.Position

        if #killerPositions > 0 then
            for _, kPos in ipairs(killerPositions) do
                if flatDist(hrpPos, kPos) < ignoreRadius then
                    clearDetour()
                    local escapeVec = flatDir(kPos, hrpPos)
                    if escapeVec.Magnitude > 0.01 then
                        bodyVel.Velocity = escapeVec * speed
                    else
                        bodyVel.Velocity = Vector3.zero
                    end
                    return
                end
            end
        end

        if cacheExitsOpen and #cacheExits > 0 then
            local reachable = {}
            for _, ePos in ipairs(cacheExits) do
                if flatDist(hrpPos, ePos) <= MAX_EXIT_DISTANCE then
                    table.insert(reachable, ePos)
                end
            end

            if #reachable > 0 then
                local bestExitPos = nil
                local bestScore = -math.huge

                for _, ePos in ipairs(reachable) do
                    local score
                    if #killerPositions > 0 then
                        local minDistToKiller = math.huge
                        for _, kPos in ipairs(killerPositions) do
                            local d = flatDist(ePos, kPos)
                            if d < minDistToKiller then minDistToKiller = d end
                        end
                        score = minDistToKiller
                    else
                        score = -flatDist(hrpPos, ePos)
                    end
                    if score > bestScore then
                        bestScore = score
                        bestExitPos = ePos
                    end
                end

                if bestExitPos then
                    local dToExit = flatDist(hrpPos, bestExitPos)
                    if dToExit < 5 then
                        bodyVel.Velocity = Vector3.zero
                        Core.HRP.CFrame = CFrame.new(bestExitPos)
                        Core.HRP.AssemblyLinearVelocity = Vector3.zero
                        return
                    end

                    local moveTarget = bestExitPos
                    if #killerPositions > 0 then
                        local detourPos = updateDetour(hrpPos, bestExitPos, killerPositions, ignoreRadius, now)
                        if detourPos then moveTarget = detourPos end
                    else
                        clearDetour()
                    end

                    local dir = flatDir(hrpPos, moveTarget)
                    if dir.Magnitude < 0.01 then
                        bodyVel.Velocity = Vector3.zero
                        return
                    end
                    bodyVel.Velocity = dir * speed
                    return
                end
            end
        end

        clearDetour()

        local items = Core.getLootItems()
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
                    local d3 = (pos - hrpPos).Magnitude
                    if d3 <= MAX_LOOT_DISTANCE then
                        local skip = false
                        if Core.settings.ignoreMurder then
                            for _, kPos in ipairs(killerPositions) do
                                if flatDist(pos, kPos) <= ignoreRadius then
                                    skip = true
                                    break
                                end
                            end
                        end
                        if not skip then
                            local d = flatDist(pos, hrpPos)
                            if d < nearestDist then
                                nearestPos, nearestDist = pos, d
                            end
                        end
                    end
                end
            end
        end

        if not nearestPos then
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

        if #killerPositions > 0 then
            local detourPos = updateDetour(hrpPos, nearestPos, killerPositions, ignoreRadius, now)
            if detourPos then
                moveTarget = detourPos
            end
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