-- language: Lua, target: Roblox (Kemerovo RP), executor any
-- apathy v2 | Rayfield Amethyst | car flight (no spin) + player/car noclip + ESP

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ===================== STATE =====================
local vehicleFlyEnabled = false
local vehicleFlyActive = false
local vehicleSpeed = 120
local vehicleRoot = nil
local vehicleBV = nil
local vehicleConn = nil
local vehicleMonitor = nil

local playerNoclip = false
local carNoclip = false
local playerNoclipConn = nil
local carNoclipConn = nil
local originalCanCollide = {}
local carOriginalCanCollide = {}

local espEnabled = false
local espObjects = {} -- [player] = {box, name, dist}

-- ===================== VEHICLE HELPERS =====================
local function getVehicleRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or not humanoid.Sit then return nil end
    local seat = humanoid.SeatPart
    if not seat then return nil end
    local model = seat:FindFirstAncestorOfClass("Model")
    if model and model.PrimaryPart then
        return model.PrimaryPart, model
    end
    return seat, seat.Parent
end

local function stopVehicleFly()
    vehicleFlyActive = false
    if vehicleConn then
        vehicleConn:Disconnect()
        vehicleConn = nil
    end
    if vehicleBV then
        vehicleBV:Destroy()
        vehicleBV = nil
    end
    -- zero angular velocity to kill residual spin
    if vehicleRoot and vehicleRoot.Parent then
        vehicleRoot.AssemblyAngularVelocity = Vector3.zero
    end
    vehicleRoot = nil
end

local function startVehicleFly()
    if vehicleFlyActive then return end
    local root = getVehicleRoot()
    if not root then return end

    vehicleRoot = root
    vehicleFlyActive = true

    -- only BodyVelocity — no BodyGyro → no forced rotation / camera fight
    vehicleBV = Instance.new("BodyVelocity")
    vehicleBV.Name = "ApathyFly"
    vehicleBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    vehicleBV.P = 10000
    vehicleBV.Velocity = Vector3.zero
    vehicleBV.Parent = vehicleRoot

    vehicleConn = RunService.Heartbeat:Connect(function()
        if not vehicleFlyEnabled or not vehicleRoot or not vehicleRoot.Parent then
            stopVehicleFly()
            return
        end

        -- kill any residual spin every frame
        vehicleRoot.AssemblyAngularVelocity = Vector3.zero

        local camCF = Camera.CFrame
        local move = Vector3.zero

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            move = move + camCF.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            move = move - camCF.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            move = move - camCF.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            move = move + camCF.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.E) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            move = move + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            move = move - Vector3.new(0, 1, 0)
        end

        if move.Magnitude > 0 then
            move = move.Unit * vehicleSpeed
        end

        vehicleBV.Velocity = move
    end)
end

local function setVehicleFly(state)
    vehicleFlyEnabled = state
    if state then
        if not vehicleMonitor then
            vehicleMonitor = RunService.Heartbeat:Connect(function()
                if not vehicleFlyEnabled then return end
                local root = getVehicleRoot()
                if root then
                    if not vehicleFlyActive then
                        startVehicleFly()
                    end
                else
                    if vehicleFlyActive then
                        stopVehicleFly()
                    end
                end
            end)
        end
        startVehicleFly()
    else
        stopVehicleFly()
        if vehicleMonitor then
            vehicleMonitor:Disconnect()
            vehicleMonitor = nil
        end
    end
end

-- ===================== NOCLIP =====================
local function setPlayerNoclip(state)
    playerNoclip = state
    if state then
        if not playerNoclipConn then
            playerNoclipConn = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character
                if not char then return end
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if originalCanCollide[part] == nil then
                            originalCanCollide[part] = part.CanCollide
                        end
                        part.CanCollide = false
                    end
                end
            end)
        end
    else
        if playerNoclipConn then
            playerNoclipConn:Disconnect()
            playerNoclipConn = nil
        end
        local char = LocalPlayer.Character
        if char then
            for part, value in pairs(originalCanCollide) do
                if part and part.Parent then
                    part.CanCollide = value
                end
            end
        end
        table.clear(originalCanCollide)
    end
end

local function setCarNoclip(state)
    carNoclip = state
    if state then
        if not carNoclipConn then
            carNoclipConn = RunService.Stepped:Connect(function()
                local _, model = getVehicleRoot()
                if not model then return end
                for _, part in ipairs(model:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if carOriginalCanCollide[part] == nil then
                            carOriginalCanCollide[part] = part.CanCollide
                        end
                        part.CanCollide = false
                    end
                end
            end)
        end
    else
        if carNoclipConn then
            carNoclipConn:Disconnect()
            carNoclipConn = nil
        end
        for part, value in pairs(carOriginalCanCollide) do
            if part and part.Parent then
                part.CanCollide = value
            end
        end
        table.clear(carOriginalCanCollide)
    end
end

-- ===================== ESP =====================
local function clearESP()
    for player, objs in pairs(espObjects) do
        if objs.box then objs.box:Destroy() end
        if objs.name then objs.name:Destroy() end
        if objs.dist then objs.dist:Destroy() end
    end
    table.clear(espObjects)
end

local function createESP(player)
    if player == LocalPlayer then return end
    if espObjects[player] then return end

    local box = Drawing.new("Square")
    box.Thickness = 1.5
    box.Filled = false
    box.Color = Color3.fromRGB(170, 100, 255)
    box.Visible = false

    local name = Drawing.new("Text")
    name.Size = 14
    name.Center = true
    name.Outline = true
    name.Color = Color3.fromRGB(255, 255, 255)
    name.Visible = false

    local dist = Drawing.new("Text")
    dist.Size = 12
    dist.Center = true
    dist.Outline = true
    dist.Color = Color3.fromRGB(180, 180, 255)
    dist.Visible = false

    espObjects[player] = {box = box, name = name, dist = dist}
end

local function updateESP()
    if not espEnabled then return end

    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    for player, objs in pairs(espObjects) do
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")

        if root and humanoid and humanoid.Health > 0 then
            local pos, onScreen = Camera:WorldToViewportPoint(root.Position)
            if onScreen and pos.Z > 0 then
                local size = 2000 / pos.Z
                objs.box.Size = Vector2.new(size * 0.7, size * 1.4)
                objs.box.Position = Vector2.new(pos.X - objs.box.Size.X / 2, pos.Y - objs.box.Size.Y / 2)
                objs.box.Visible = true

                objs.name.Text = player.Name
                objs.name.Position = Vector2.new(pos.X, pos.Y - size * 0.8)
                objs.name.Visible = true

                local distance = (myRoot.Position - root.Position).Magnitude
                objs.dist.Text = string.format("[%d]", math.floor(distance))
                objs.dist.Position = Vector2.new(pos.X, pos.Y + size * 0.75)
                objs.dist.Visible = true
            else
                objs.box.Visible = false
                objs.name.Visible = false
                objs.dist.Visible = false
            end
        else
            objs.box.Visible = false
            objs.name.Visible = false
            objs.dist.Visible = false
        end
    end
end

local function setESP(state)
    espEnabled = state
    if state then
        for _, player in ipairs(Players:GetPlayers()) do
            createESP(player)
        end
        if not _G.ApathyESPConn then
            _G.ApathyESPConn = RunService.RenderStepped:Connect(updateESP)
        end
    else
        clearESP()
        if _G.ApathyESPConn then
            _G.ApathyESPConn:Disconnect()
            _G.ApathyESPConn = nil
        end
    end
end

Players.PlayerAdded:Connect(function(player)
    if espEnabled then
        createESP(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if espObjects[player] then
        local objs = espObjects[player]
        if objs.box then objs.box:Destroy() end
        if objs.name then objs.name:Destroy() end
        if objs.dist then objs.dist:Destroy() end
        espObjects[player] = nil
    end
end)

-- cleanup
LocalPlayer.CharacterRemoving:Connect(function()
    stopVehicleFly()
    if playerNoclip then setPlayerNoclip(false) end
    if carNoclip then setCarNoclip(false) end
end)

-- ===================== UI =====================
local Window = Rayfield:CreateWindow({
    Name = "apathy v2",
    LoadingTitle = "apathy v2",
    LoadingSubtitle = "Kemerovo RP",
    Theme = "Amethyst",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "apathy",
        FileName = "apathy_v2"
    },
    Discord = { Enabled = false },
    KeySystem = false
})

local MainTab = Window:CreateTab("Main", 4483362458)

MainTab:CreateSection("Vehicle")

MainTab:CreateToggle({
    Name = "Car Flight",
    CurrentValue = false,
    Flag = "CarFlight",
    Callback = function(Value)
        setVehicleFly(Value)
        Rayfield:Notify({
            Title = "apathy v2",
            Content = Value and "Car Flight ON — WASD + E/Q  (no spin)" or "Car Flight OFF",
            Duration = 3
        })
    end
})

MainTab:CreateSlider({
    Name = "Fly Speed",
    Range = {20, 400},
    Increment = 10,
    Suffix = " studs",
    CurrentValue = 120,
    Flag = "FlySpeed",
    Callback = function(Value)
        vehicleSpeed = Value
    end
})

MainTab:CreateToggle({
    Name = "Car Noclip",
    CurrentValue = false,
    Flag = "CarNoclip",
    Callback = function(Value)
        setCarNoclip(Value)
        Rayfield:Notify({
            Title = "apathy v2",
            Content = Value and "Car Noclip ON" or "Car Noclip OFF",
            Duration = 3
        })
    end
})

MainTab:CreateSection("Player")

MainTab:CreateToggle({
    Name = "Player Noclip",
    CurrentValue = false,
    Flag = "PlayerNoclip",
    Callback = function(Value)
        setPlayerNoclip(Value)
        Rayfield:Notify({
            Title = "apathy v2",
            Content = Value and "Player Noclip ON" or "Player Noclip OFF",
            Duration = 3
        })
    end
})

MainTab:CreateSection("Visuals")

MainTab:CreateToggle({
    Name = "ESP",
    CurrentValue = false,
    Flag = "ESP",
    Callback = function(Value)
        setESP(Value)
        Rayfield:Notify({
            Title = "apathy v2",
            Content = Value and "ESP ON" or "ESP OFF",
            Duration = 3
        })
    end
})

MainTab:CreateSection("Info")
MainTab:CreateParagraph({
    Title = "Controls",
    Content = "Car Flight: sit → toggle → WASD move, E/Space up, Q/Ctrl down. No BodyGyro = no spin, camera free.\nCar Noclip: makes the whole vehicle pass through walls.\nESP: boxes + name + distance on all players."
})

Rayfield:Notify({
    Title = "apathy v2",
    Content = "loaded — spin fixed · ESP · car noclip",
    Duration = 4
})

Rayfield:LoadConfiguration()