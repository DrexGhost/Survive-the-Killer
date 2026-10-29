local Core, GUI = ...
local RunService = game:GetService("RunService")

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

    RunService.Stepped:Connect(function()
        if not Core.settings.autoFarmGarbage then return end
        if not Core.HRP or not Core.HRP.Parent then return end

        Core.enforceNoclip()

        if not bodyVel or not bodyVel.Parent then
            bodyVel = Instance.new("BodyVelocity")
            bodyVel.Name = "NexusXAutoFarm"
            bodyVel.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bodyVel.Velocity = Vector3.zero
            bodyVel.Parent = Core.HRP
        end

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
                    if d < nearestDist then
                        nearestPos, nearestDist = pos, d
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
        else
            local dir = nearestPos - hrpPos
            bodyVel.Velocity = dir.Unit * 500
        end
    end)

    tab.Button.MouseButton1Click:Connect(function() GUI.switchTab(tab, page) end)
    return tab, page
end
return build