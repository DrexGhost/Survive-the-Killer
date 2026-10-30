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
    local MAX_SAFE_DOWNED_DISTANCE = 500
    local MAX_SELF_RESCUE_DISTANCE = 500
    local TRAP_AVOID_RADIUS = 5
    local REVIVE_CLICK_INTERVAL = 0.15
    local REVIVE_BLACKLIST_TIME = 10
    local REVIVE_STUCK_TIME = 5
    local DOWNED_FLY_STEP = 100 / 60
    local ESCAPE_RADIUS = 5 -- Жесткий радиус побега от убийцы

    local exitWiggleActive = false
    local lastExitWiggleTime = 0
    local lastRevive = 0
    local currentReviveTarget = nil
    local currentReviveStart = 0
    local reviveBlacklist = {}

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
            exitWiggleActive = false
            lastExitWiggleTime = 0
            lastRevive = 0
            currentReviveTarget = nil
            reviveBlacklist = {}
        end
    end, "autoFarmGarbage")

    GUI.makeSlider(page, "Farm Speed", 16, 500, Core.settings.farmSpeed or 100, 3, function(v)
        Core.settings.farmSpeed = v
    end, "farmSpeed")

    GUI.makeToggle(page, "Ignore Killer", "Не лететь рядом с убийцей (мусор, спасение)", Core.settings.ignoreMurder, 4, function(v)
        Core.settings.ignoreMurder = v
    end, "ignoreMurder")

    GUI.makeSlider(page, "Ignore Radius", 1, 100, Core.settings.ignoreMurderRadius or 10, 5, function(v)
        Core.settings.ignoreMurderRadius = v
    end, "ignoreMurderRadius")

    GUI.makeToggle(page, "Safe Downed", "Спасать нокнутых игроков (макс. 500м)", Core.settings.safeDowned, 6, function(v)
        Core.settings.safeDowned = v
        if not v then
            currentReviveTarget = nil
            reviveBlacklist = {}
        end
    end, "safeDowned")

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

    local function isDead(p)
        if not p or not p.Character then return true end
        local hum = p.Character:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return true end
        return false
    end

    local function isDowned(p)
        if isDead(p) then return false end
        local char = p.Character
        local hum = char:FindFirstChildOfClass("Humanoid")
        for _, a in ipairs({"Downed", "IsDowned", "Down", "Crawling", "IsCrawling", "Knocked", "IsKnocked"}) do
            if char:GetAttribute(a) == true or p:GetAttribute(a) == true then return true end
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

    local function isAliveNormal(p)
        return not isDead(p) and not isDowned(p)
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

    local function getNonDownedPlayer(hrpPos, killerPositions, ignoreKiller, ignoreRadius)
        local best, bestDist = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                if isAliveNormal(p) then
                    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local skip = false
                        if ignoreKiller then
                            for _, kPos in ipairs(killerPositions) do
                                if flatDist(hrp.Position, kPos) <= ignoreRadius then
                                    skip = true
                                    break
                                end
                            end
                        end
                        if not skip then
                            local d = flatDist(hrp.Position, hrpPos)
                            if d <= MAX_SELF_RESCUE_DISTANCE and d < bestDist then
                                best = { pos = hrp.Position, player = p }
                                bestDist = d
                            end
                        end
                    end
                end
            end
        end
        return best, bestDist
    end

    local function getDownedPlayer(hrpPos, killerPositions, ignoreKiller, ignoreRadius, now)
        local best, bestDist = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                if isDowned(p) then
                    local bl = reviveBlacklist[p]
                    if not bl or now >= bl then
                        local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local skip = false
                            if ignoreKiller then
                                for _, kPos in ipairs(killerPositions) do
                                    if flatDist(hrp.Position, kPos) <= ignoreRadius then
                                        skip = true
                                        break
                                    end
                                end
                            end
                            if not skip then
                                local d = flatDist(hrp.Position, hrpPos)
                                if d <= MAX_SAFE_DOWNED_DISTANCE and d < bestDist then
                                    best = { pos = hrp.Position, player = p }
                                    bestDist = d
                                end
                            end
                        end
                    end
                end
            end
        end
        return best, bestDist
    end

    local function tryRevive(targetPlayer)
        if not targetPlayer or not targetPlayer.Character then return end

        for _, d in ipairs(targetPlayer.Character:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local hold = d.HoldDuration or 0
                pcall(function() d:InputHoldBegin() end)
                if hold > 0 then
                    task.delay(hold + 0.05, function()
                        pcall(function() d:InputHoldEnd() end)
                    end)
                else
                    pcall(function() d:InputHoldEnd() end)
                end
                return
            end
        end

        local remote = Core.findRemote("revive")
            or Core.findRemote("rescue")
            or Core.findRemote("help")
            or Core.findRemote("save")
            or Core.findRemote("pickup")
        if remote then
            pcall(function()
                if remote:IsA("RemoteEvent") then
                    remote:FireServer(targetPlayer)
                elseif remote:IsA("RemoteFunction") then
                    remote:InvokeServer(targetPlayer)
                end
            end)
        end
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

    local function pickSideDir(hrpPos, targetPos, obstaclePos)
        local toKX = obstaclePos.X - hrpPos.X
        local toKZ = obstaclePos.Z - hrpPos.Z
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

    local function updateDetour(hrpPos, targetPos, obstacles, now)
        if not obstacles or #obstacles == 0 then
            clearDetour()
            return nil
        end

        local blocking = nil
        for _, ob in ipairs(obstacles) do
            if lineHitsCircle(hrpPos, targetPos, ob.pos, ob.radius) then
                blocking = ob
                break
            end
        end

        if not blocking then
            clearDetour()
            return nil
        end

        if detour then
            local distToDetour = flatDist(hrpPos, detour.target)
            local reached = distToDetour < 6
            local expired = now >= detour.expires

            if not reached and not expired then
                local targetSafe = true
                for _, ob in ipairs(obstacles) do
                    if flatDist(detour.target, ob.pos) <= ob.radius then
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
            side = pickSideDir(hrpPos, targetPos, blocking.pos)
        end

        local offset = blocking.radius + 10
        local newTarget = Vector3.new(
            blocking.pos.X + side.X * offset,
            hrpPos.Y,
            blocking.pos.Z + side.Z * offset
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

    local function doExitWiggle(exitPos, dirToExit)
        if exitWiggleActive then return end
        exitWiggleActive = true

        task.spawn(function()
            local fwd = Vector3.new(dirToExit.X, 0, dirToExit.Z)
            if fwd.Magnitude < 0.01 then fwd = Vector3.new(0, 0, -1) end
            fwd = fwd.Unit
            local right = Vector3.new(-fwd.Z, 0, fwd.X)

            local baseY = exitPos.Y
            if Core.HRP and Core.HRP.Parent then
                baseY = Core.HRP.Position.Y
            end

            local offsets = {
                right * 5,
                -right * 5,
                fwd * 5,
                -fwd * 5,
            }

            for _, off in ipairs(offsets) do
                if not Core.HRP or not Core.HRP.Parent then break end
                Core.HRP.CFrame = CFrame.new(Vector3.new(exitPos.X + off.X, baseY, exitPos.Z + off.Z))
                task.wait(0.12)
            end

            if Core.HRP and Core.HRP.Parent then
                Core.HRP.CFrame = CFrame.new(Vector3.new(exitPos.X, baseY, exitPos.Z))
                Core.HRP.AssemblyLinearVelocity = Vector3.zero
            end

            exitWiggleActive = false
            lastExitWiggleTime = os.clock()
        end)
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
        local trapPositions = Core.cachedTraps
        local ignoreKiller = Core.settings.ignoreMurder
        local ignoreRadius = Core.settings.ignoreMurderRadius or 10
        local speed = Core.settings.farmSpeed or 100

        local hrpPos = Core.HRP.Position

        if isDowned(LocalPlayer) then
            bodyVel.Velocity = Vector3.zero
            local target, dist = getNonDownedPlayer(hrpPos, killerPositions, ignoreKiller, ignoreRadius)
            if target then
                if dist < 5 then
                    Core.HRP.CFrame = CFrame.new(target.pos)
                    Core.HRP.AssemblyLinearVelocity = Vector3.zero
                else
                    local dir = flatDir(hrpPos, target.pos)
                    local step = math.min(DOWNED_FLY_STEP, dist)
                    local newPos = Vector3.new(
                        hrpPos.X + dir.X * step,
                        hrpPos.Y,
                        hrpPos.Z + dir.Z * step
                    )
                    Core.HRP.CFrame = CFrame.new(newPos)
                end
            end
            return
        end

        if exitWiggleActive then
            bodyVel.Velocity = Vector3.zero
            return
        end

        -- ИСПОЛЬЗУЕМ ESCAPE_RADIUS ДЛЯ ПОБЕГА (ЖЕСТКО 5)
        if #killerPositions > 0 then
            for _, kPos in ipairs(killerPositions) do
                if flatDist(hrpPos, kPos) < ESCAPE_RADIUS then
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

        if Core.settings.safeDowned then
            local target, dist = getDownedPlayer(hrpPos, killerPositions, ignoreKiller, ignoreRadius, now)

            if target then
                if currentReviveTarget ~= target.player then
                    currentReviveTarget = target.player
                    currentReviveStart = now
                elseif dist < 10 and now - currentReviveStart > REVIVE_STUCK_TIME then
                    reviveBlacklist[target.player] = now + REVIVE_BLACKLIST_TIME
                    currentReviveTarget = nil
                    target = nil
                end
            end

            if target then
                if dist < 5 then
                    bodyVel.Velocity = Vector3.zero
                    Core.HRP.CFrame = CFrame.new(target.pos)
                    Core.HRP.AssemblyLinearVelocity = Vector3.zero
                    if now - lastRevive >= REVIVE_CLICK_INTERVAL then
                        lastRevive = now
                        tryRevive(target.player)
                    end
                else
                    local moveTarget = target.pos
                    
                    local obs = {}
                    for _, kPos in ipairs(killerPositions) do
                        table.insert(obs, { pos = kPos, radius = ignoreRadius })
                    end
                    for _, tPos in ipairs(trapPositions) do
                        table.insert(obs, { pos = tPos, radius = TRAP_AVOID_RADIUS })
                    end

                    if #obs > 0 then
                        local detourPos = updateDetour(hrpPos, target.pos, obs, now)
                        if detourPos then moveTarget = detourPos end
                    else
                        clearDetour()
                    end

                    local dir = flatDir(hrpPos, moveTarget)
                    if dir.Magnitude < 0.01 then
                        bodyVel.Velocity = Vector3.zero
                    else
                        bodyVel.Velocity = dir * speed
                    end
                end
                return
            end
            currentReviveTarget = nil
        end

        local obstacles = {}
        for _, kPos in ipairs(killerPositions) do
            table.insert(obstacles, { pos = kPos, radius = ignoreRadius })
        end
        for _, tPos in ipairs(trapPositions) do
            table.insert(obstacles, { pos = tPos, radius = TRAP_AVOID_RADIUS })
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
                        if now - lastExitWiggleTime > 2 then
                            local dirToExit = flatDir(hrpPos, bestExitPos)
                            Core.HRP.CFrame = CFrame.new(bestExitPos)
                            Core.HRP.AssemblyLinearVelocity = Vector3.zero
                            doExitWiggle(bestExitPos, dirToExit)
                        end
                        return
                    end

                    local moveTarget = bestExitPos
                    if #obstacles > 0 then
                        local detourPos = updateDetour(hrpPos, bestExitPos, obstacles, now)
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
                        if ignoreKiller then
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

        if #obstacles > 0 then
            local detourPos = updateDetour(hrpPos, nearestPos, obstacles, now)
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