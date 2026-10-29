local Core, GUI, ESPDisplay = ...
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local function build()
    local tab = GUI.makeTab("ESP", 3, "combat")
    local page = GUI.makePage()
    local T = Core.T

    GUI.makeSectionHeader(page, "Players", 1)

    GUI.makeToggle(page, "Esp Player", "Полностью выключает ESP игроков", Core.settings.espPlayers, 2, function(v)
        Core.settings.espPlayers = v
        if not v then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    ESPDisplay.remove(p.Character)
                end
            end
        end
    end, "espPlayers")

    GUI.makeToggle(page, "Esp Innocent", "Показывает обычных игроков белым", Core.settings.espInnocent, 3, function(v)
        Core.settings.espInnocent = v
        if not v then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and Core.getRole(p) == "Innocent" then
                    ESPDisplay.remove(p.Character)
                end
            end
        end
    end, "espInnocent")

    GUI.makeToggle(page, "Esp Killer", "Показывает убийцу красным", Core.settings.espKiller, 4, function(v)
        Core.settings.espKiller = v
        if not v then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and Core.getRole(p) == "Killer" then
                    ESPDisplay.remove(p.Character)
                end
            end
        end
    end, "espKiller")

    GUI.makeSectionHeader(page, "Other", 5)

    GUI.makeToggle(page, "Esp Items", "Показывает предметы зелёным", Core.settings.espItems, 6, function(v)
        Core.settings.espItems = v
    end, "espItems")

    local lastUpdate = 0
    local lastItemsScan = 0
    local trackedItems = {}

    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        if now - lastUpdate < 0.2 then return end
        lastUpdate = now

        ESPDisplay.update()

        if Core.settings.espPlayers then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    local role = Core.getRole(p)
                    if role == "Killer" and Core.settings.espKiller then
                        ESPDisplay.add(p.Character, {color = T.red, name = p.Name})
                    elseif role == "Innocent" and Core.settings.espInnocent then
                        ESPDisplay.add(p.Character, {color = T.white, name = p.Name})
                    else
                        ESPDisplay.remove(p.Character)
                    end
                end
            end
        end

        if now - lastItemsScan >= 2 then
            lastItemsScan = now
            if Core.settings.espItems then
                local seen = {}
                for _, obj in ipairs(workspace:GetDescendants()) do
                    if obj:IsA("Model") or obj:IsA("BasePart") then
                        if Core.isItem(obj) then
                            seen[obj] = true
                            ESPDisplay.add(obj, {color = T.green, distance = true})
                        end
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
    end)

    tab.Button.MouseButton1Click:Connect(function() GUI.switchTab(tab, page) end)
    return tab, page
end
return build