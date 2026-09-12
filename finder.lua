-- Draggable GUI Button to Join Low Player Server in Roblox with clickable button

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- Create ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ServerJoinGui"
screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Create Frame (Button)
local frame = Instance.new("TextButton")
frame.Size = UDim2.new(0, 180, 0, 50)
frame.Position = UDim2.new(0, 50, 0, 50)
frame.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
frame.BorderSizePixel = 0
frame.Parent = screenGui
frame.Active = true
frame.Draggable = true
frame.Text = "Join Low Player Server"
frame.Font = Enum.Font.SourceSansBold
frame.TextSize = 18
frame.TextColor3 = Color3.new(1, 1, 1)

-- Function to get servers with low players (<=1) and pick one
local function joinLowPlayerServer()
    local placeId = game.PlaceId
    local servers = {}
    local cursor = ""

    repeat
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?limit=100&sortOrder=Asc&cursor=%s"):format(placeId, cursor)
        local success, response = pcall(function()
            return HttpService:GetAsync(url)
        end)
        if not success then
            warn("Failed to get server list.")
            return
        end

        local data = HttpService:JSONDecode(response)

        for _, server in pairs(data.data) do
            -- Filter servers with 1 or fewer players
            if server.playing <= 1 and server.maxPlayers > 1 then
                table.insert(servers, server)
            end
        end

        cursor = data.nextPageCursor or ""
    until cursor == ""

    if #servers == 0 then
        warn("No servers with 1 or fewer players found.")
        return
    end

    -- Since we can't get real ping from servers, just pick the first server found
    local serverToJoin = servers[1]

    TeleportService:TeleportToPlaceInstance(placeId, serverToJoin.id, Players.LocalPlayer)
end

-- Connect button click
frame.MouseButton1Click:Connect(function()
    joinLowPlayerServer()
end)
