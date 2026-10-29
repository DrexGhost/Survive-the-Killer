local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Core = ...
local ESPDisplay = {}

ESPDisplay._entries = {}

function ESPDisplay.add(adornee, opts)
    if not adornee then return end
    opts = opts or {}
    local color = opts.color or Color3.fromRGB(255, 255, 255)
    local fillTransparency = opts.fillTransparency or 0.5
    local outlineTransparency = opts.outlineTransparency or 0
    local outlineColor = opts.outlineColor or color
    local depthMode = opts.depthMode or Enum.HighlightDepthMode.AlwaysOnTop
    local entry = ESPDisplay._entries[adornee]

    if entry and entry.Highlight and entry.Highlight.Parent then
        entry.Highlight.FillColor = color
        entry.Highlight.FillTransparency = fillTransparency
        entry.Highlight.OutlineColor = outlineColor
        entry.Highlight.OutlineTransparency = outlineTransparency
        entry.Highlight.DepthMode = depthMode
        if entry.NameLabel then entry.NameLabel.TextColor3 = color end
        if entry.DistanceLabel then entry.DistanceLabel.TextColor3 = color end
        return
    end

    local h = Instance.new("Highlight")
    h.Name = "NexusXESP"
    h.FillColor = color
    h.FillTransparency = fillTransparency
    h.OutlineColor = outlineColor
    h.OutlineTransparency = outlineTransparency
    h.DepthMode = depthMode
    h.Adornee = adornee
    h.Parent = PlayerGui

    local bb = Instance.new("BillboardGui")
    bb.Name = "NexusXESPBB"
    bb.Adornee = adornee
    bb.Size = UDim2.new(0, 200, 0, 40)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.MaxDistance = 1000
    bb.Parent = PlayerGui

    local nameLabel
    if opts.name then
        nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = opts.name
        nameLabel.TextColor3 = color
        nameLabel.TextSize = 14
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextStrokeTransparency = 0
        nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        nameLabel.Parent = bb
    end

    local distanceLabel
    if opts.distance ~= false then
        distanceLabel = Instance.new("TextLabel")
        distanceLabel.Size = UDim2.new(1, 0, 0.5, 0)
        distanceLabel.Position = UDim2.new(0, 0, 0.5, 0)
        distanceLabel.BackgroundTransparency = 1
        distanceLabel.Text = ""
        distanceLabel.TextColor3 = color
        distanceLabel.TextSize = 12
        distanceLabel.Font = Enum.Font.Gotham
        distanceLabel.TextStrokeTransparency = 0
        distanceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        distanceLabel.Parent = bb
    end

    ESPDisplay._entries[adornee] = {
        Highlight = h,
        Billboard = bb,
        NameLabel = nameLabel,
        DistanceLabel = distanceLabel,
        Color = color,
        Adornee = adornee,
    }
end

function ESPDisplay.remove(adornee)
    local entry = ESPDisplay._entries[adornee]
    if not entry then return end
    if entry.Highlight then entry.Highlight:Destroy() end
    if entry.Billboard then entry.Billboard:Destroy() end
    ESPDisplay._entries[adornee] = nil
end

function ESPDisplay.clear()
    local list = {}
    for adornee in pairs(ESPDisplay._entries) do table.insert(list, adornee) end
    for _, adornee in ipairs(list) do ESPDisplay.remove(adornee) end
end

function ESPDisplay.update()
    local hrp = Core and Core.HRP
    if not hrp then return end
    local rootPos = hrp.Position
    for adornee, entry in pairs(ESPDisplay._entries) do
        if not adornee or not adornee.Parent then
            ESPDisplay.remove(adornee)
        elseif entry.DistanceLabel then
            local targetPos
            if adornee:IsA("Model") then
                local ok, pivot = pcall(function() return adornee:GetPivot().Position end)
                if ok then targetPos = pivot end
            elseif adornee:IsA("BasePart") then
                targetPos = adornee.Position
            end
            if targetPos then
                local d = math.floor((rootPos - targetPos).Magnitude)
                entry.DistanceLabel.Text = "[" .. d .. "m]"
            end
        end
    end
end

return ESPDisplay