-- Draggable GUI Button to Join Low Player Server in Roblox

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- Create ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ServerJoinGui"
screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") -- safer parenting

-- Create Frame (Button)
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 150, 0, 50)
frame.Position = UDim2.new(0, 50, 0, 50)
frame.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
frame.BorderSizePixel = 0
frame.Parent = screenGui
frame.Active = true
frame.Draggable = true

-- Create TextLabel inside Frame
local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 1, 0)
label.BackgroundTransparency = 1
label.Text = "Join Low Player Server"
label.TextColor3 = Color3.new(1, 1, 1)
label.Font = Enum.Font.SourceSansBold
label.TextSize = 18
label.Parent = frame

-- Function to get servers with 1 player and join one
local function joinLowPlayerServer()
    local placeId = game.PlaceId
    local servers = {}
    local cursor = ""

    -- Loop to paginate through servers if needed
    repeat
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?limit=100&sortOrder=Asc&cursor=%s"):format(placeId, cursor)
        local response = HttpService:GetAsync(url)
        local data = HttpService:JSONDecode(response)

        for _, server in pairs(data.data) do
            -- Check if server has exactly 1 player and is not full
            if server.playing == 1 and server.maxPlayers > 1 then
                table.insert(servers, server)
            end
        end

        cursor = data.nextPageCursor or ""
    until cursor == ""

    if #servers == 0 then
        warn("No servers with exactly 1 player found.")
        return
    end

    -- For simplicity, join the first server found with 1 player
    local serverToJoin = servers[1]

    -- Teleport to that server
    TeleportService:TeleportToPlaceInstance(placeId, serverToJoin.id, Players.LocalPlayer)
end

-- Connect button click
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        joinLowPlayerServer()
    end
end)
