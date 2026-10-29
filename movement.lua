local Core, GUI = ...
local RunService = game:GetService("RunService")

local function build()
    local tab = GUI.makeTab("Movement", 5, "motion")
    local page = GUI.makePage()

    GUI.makeSectionHeader(page, "Movement", 1)

    GUI.makeToggle(page, "Noclip", "Проходить сквозь стены", Core.settings.noclip, 2, function(v)
        Core.settings.noclip = v
        if v then
            Core.setNoclip(true)
            Core.NoclipActive = true
        else
            Core.setNoclip(false)
            Core.NoclipActive = false
        end
    end, "noclip")

    GUI.makeToggle(page, "Speed", "Ускорение", Core.settings.speed, 3, function(v)
        Core.settings.speed = v
        if not v and Core.Hum then Core.Hum.WalkSpeed = 16 end
    end, "speed")

    GUI.makeSlider(page, "Speed Value", 16, 500, Core.settings.walkSpeed, 4, function(v)
        Core.settings.walkSpeed = v
    end, "walkSpeed")

    RunService.Stepped:Connect(function()
        if Core.settings.noclip then
            Core.enforceNoclip()
        end
        if Core.Hum and Core.settings.speed then
            if Core.Hum.WalkSpeed ~= Core.settings.walkSpeed then
                Core.Hum.WalkSpeed = Core.settings.walkSpeed
            end
        end
    end)

    tab.Button.MouseButton1Click:Connect(function() GUI.switchTab(tab, page) end)
    return tab, page
end
return build