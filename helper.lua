local Core, GUI = ...

local function build()
    local tab = GUI.makeTab("Helper", 2, "helper")
    local page = GUI.makePage()
    local T = Core.T

    local holder = Instance.new("Frame", page)
    holder.Size = UDim2.new(1, 0, 0, 260)
    holder.BackgroundTransparency = 1
    holder.LayoutOrder = 1

    local lbl = Instance.new("TextLabel", holder)
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "Soon"
    lbl.TextColor3 = T.accent
    lbl.TextSize = 42
    lbl.Font = Enum.Font.GothamBlack
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.TextYAlignment = Enum.TextYAlignment.Center

    tab.Button.MouseButton1Click:Connect(function() GUI.switchTab(tab, page) end)
    return tab, page
end
return build