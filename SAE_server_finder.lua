--// Steal An Egg - Public Server Finder
--// Place ID: 107778070777162
--// Scans up to 700 raw public-server results
--// BEST = lowest player count, then preferred 40-50ms ping
--// Rate-limit safe / duplicate-scan protected

--------------------------------------------------
--// DUPLICATE EXECUTION PROTECTION
--------------------------------------------------

local genv = getgenv and getgenv() or _G

genv.StealEggServerFinderToken = (genv.StealEggServerFinderToken or 0) + 1
local MY_TOKEN = genv.StealEggServerFinderToken

pcall(function()
    local CoreGui = game:GetService("CoreGui")
    local oldGui = CoreGui:FindFirstChild("StealEggServerFinder")

    if oldGui then
        oldGui:Destroy()
    end
end)

--------------------------------------------------
--// SERVICES
--------------------------------------------------

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

--------------------------------------------------
--// SETTINGS
--------------------------------------------------

local PLACE_ID = 107778070777162

local MAX_PLAYERS = 7
local TARGET = 700
local LIMIT = 100

-- Request pacing
local DELAY = 1.15
local RETRIES = 5

-- Rate-limit maximum cooldown
local MAX_BACKOFF = 20

--------------------------------------------------
--// HTTP REQUEST FUNCTION
--------------------------------------------------

local Request =
    (syn and syn.request) or
    (http and http.request) or
    http_request or
    request or
    (fluxus and fluxus.request)

if not Request then
    warn("No supported HTTP request function found.")
    return
end

--------------------------------------------------
--// UI
--------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "StealEggServerFinder"
gui.ResetOnSpawn = false
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 420, 0, 500)
main.Position = UDim2.new(0.5, -210, 0.5, -250)
main.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
main.BorderSizePixel = 0
main.Parent = gui

Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

--------------------------------------------------
--// TITLE
--------------------------------------------------

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 40)
title.Position = UDim2.new(0, 10, 0, 5)
title.BackgroundTransparency = 1
title.Text = "STEAL AN EGG • SERVER FINDER"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.Parent = main

--------------------------------------------------
--// STATUS
--------------------------------------------------

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 25)
status.Position = UDim2.new(0, 10, 0, 45)
status.BackgroundTransparency = 1
status.Text = "Ready • 0 servers"
status.TextColor3 = Color3.fromRGB(180, 180, 190)
status.TextSize = 13
status.Font = Enum.Font.Gotham
status.Parent = main

--------------------------------------------------
--// BUTTONS
--------------------------------------------------

local scan = Instance.new("TextButton")
scan.Size = UDim2.new(0, 125, 0, 35)
scan.Position = UDim2.new(0, 10, 0, 78)
scan.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
scan.Text = "RESCAN"
scan.TextColor3 = Color3.new(1, 1, 1)
scan.Font = Enum.Font.GothamBold
scan.TextSize = 13
scan.Parent = main

Instance.new("UICorner", scan).CornerRadius = UDim.new(0, 8)

local stop = scan:Clone()
stop.Position = UDim2.new(0, 145, 0, 78)
stop.Text = "STOP"
stop.Parent = main

local bestButton = scan:Clone()
bestButton.Position = UDim2.new(0, 280, 0, 78)
bestButton.Text = "BEST"
bestButton.Parent = main

--------------------------------------------------
--// SERVER LIST
--------------------------------------------------

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -20, 1, -125)
list.Position = UDim2.new(0, 10, 0, 120)
list.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.CanvasSize = UDim2.new()
list.Parent = main

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = list

--------------------------------------------------
--// DRAGGING
--------------------------------------------------

local dragging = false
local dragStart
local startPos

main.InputBegan:Connect(function(input)

    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then

        dragging = true
        dragStart = input.Position
        startPos = main.Position

        input.Changed:Connect(function()

            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end

        end)
    end
end)

UIS.InputChanged:Connect(function(input)

    if dragging and
    (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then

        local delta = input.Position - dragStart

        main.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

--------------------------------------------------
--// STATE
--------------------------------------------------

local Servers = {}
local Scanning = false
local StopScan = false

local consecutive429 = 0
local lastRequestTime = 0

--------------------------------------------------
--// TOKEN CHECK
--------------------------------------------------

local function stillValid()

    return genv.StealEggServerFinderToken == MY_TOKEN
end

--------------------------------------------------
--// CLEAR LIST
--------------------------------------------------

local function clear()

    for _, v in ipairs(list:GetChildren()) do
        if v:IsA("Frame") then
            v:Destroy()
        end
    end
end

--------------------------------------------------
--// JOIN SERVER
--------------------------------------------------

local function joinServer(id)

    if not id then
        return
    end

    TeleportService:TeleportToPlaceInstance(
        PLACE_ID,
        id,
        LocalPlayer
    )
end

--------------------------------------------------
--// SMART WAIT
--------------------------------------------------

local function smartWait(delayTime)

    local now = os.clock()
    local elapsed = now - lastRequestTime

    if elapsed < delayTime then
        task.wait(delayTime - elapsed)
    end

    lastRequestTime = os.clock()
end

--------------------------------------------------
--// ADD SERVER CARD
--------------------------------------------------

local function addServer(server)

    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -10, 0, 65)
    card.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    card.BorderSizePixel = 0
    card.Parent = list

    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    local ping = tonumber(server.ping)

    if not ping or ping <= 0 then
        ping = "?"
    end

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -110, 1, 0)
    info.Position = UDim2.new(0, 10, 0, 0)
    info.BackgroundTransparency = 1
    info.TextXAlignment = Enum.TextXAlignment.Left

    info.Text = string.format(
        "%d/%d PLAYERS • %sms\n%s",
        tonumber(server.playing) or 0,
        tonumber(server.maxPlayers) or MAX_PLAYERS,
        ping,
        tostring(server.id)
    )

    info.TextColor3 = Color3.new(1, 1, 1)
    info.TextSize = 12
    info.Font = Enum.Font.Gotham
    info.Parent = card

    local join = Instance.new("TextButton")
    join.Size = UDim2.new(0, 80, 0, 30)
    join.Position = UDim2.new(1, -90, 0.5, -15)
    join.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
    join.Text = "JOIN"
    join.TextColor3 = Color3.new(1, 1, 1)
    join.Font = Enum.Font.GothamBold
    join.TextSize = 12
    join.Parent = card

    Instance.new("UICorner", join).CornerRadius = UDim.new(0, 7)

    join.MouseButton1Click:Connect(function()

        if not stillValid() then
            return
        end

        joinServer(server.id)
    end)

    card.InputBegan:Connect(function(input)

        if input.UserInputType == Enum.UserInputType.MouseButton1 then

            if setclipboard then
                setclipboard(server.id)
                status.Text = "Copied Job ID"
            end

        end
    end)
end

--------------------------------------------------
--// RENDER
--------------------------------------------------

local function render()

    clear()

    table.sort(Servers, function(a, b)

        local ap = tonumber(a.playing) or 999
        local bp = tonumber(b.playing) or 999

        if ap == bp then

            local aq = tonumber(a.ping) or 999
            local bq = tonumber(b.ping) or 999

            return aq < bq
        end

        return ap < bp
    end)

    for _, server in ipairs(Servers) do

        if not stillValid() then
            return
        end

        addServer(server)
    end

    list.CanvasSize = UDim2.new(
        0,
        0,
        0,
        layout.AbsoluteContentSize.Y + 10
    )

    status.Text = string.format(
        "Found %d available • scanned %d/%d",
        #Servers,
        math.min(TARGET, TARGET),
        TARGET
    )
end

--------------------------------------------------
--// GET PAGE
--------------------------------------------------

local function getPage(cursor)

    local url =
        "https://games.roblox.com/v1/games/" ..
        PLACE_ID ..
        "/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=" ..
        LIMIT

    if cursor and cursor ~= "" then

        url = url ..
            "&cursor=" ..
            HttpService:UrlEncode(cursor)
    end

    for attempt = 1, RETRIES do

        if StopScan or not stillValid() then
            return nil, nil
        end

        --------------------------------------------------
        -- NORMAL REQUEST SPACING
        --------------------------------------------------

        smartWait(DELAY)

        local ok, response = pcall(function()

            return Request({
                Url = url,
                Method = "GET"
            })

        end)

        if not ok or not response then

            local retryWait = math.min(
                attempt * 2,
                8
            )

            status.Text = string.format(
                "Request failed • retrying in %ds",
                retryWait
            )

            task.wait(retryWait)

            continue
        end

        --------------------------------------------------
        -- SUCCESS
        --------------------------------------------------

        if response.StatusCode == 200 then

            consecutive429 = 0

            local success, data = pcall(function()

                return HttpService:JSONDecode(
                    response.Body
                )

            end)

            if success and data then

                return (
                    data.data or {}
                ),
                data.nextPageCursor
            end

            status.Text = "Bad response • retrying..."
            task.wait(2)

            continue
        end

        --------------------------------------------------
        -- 429 RATE LIMIT
        --------------------------------------------------

        if response.StatusCode == 429 then

            consecutive429 += 1

            local retryAfter

            pcall(function()

                if response.Headers then

                    retryAfter =
                        response.Headers["Retry-After"] or
                        response.Headers["retry-after"]

                end

            end)

            retryAfter = tonumber(retryAfter)

            -- If Roblox doesn't give Retry-After,
            -- use progressive fallback.
            if not retryAfter then

                retryAfter = math.min(
                    3 * consecutive429,
                    15
                )

            end

            -- Extra cooldown after repeated 429s
            if consecutive429 >= 3 then

                retryAfter = math.min(
                    retryAfter + 5,
                    MAX_BACKOFF
                )

            end

            status.Text = string.format(
                "Rate limited • cooling down %ds",
                math.ceil(retryAfter)
            )

            task.wait(retryAfter)

            lastRequestTime = os.clock()

            continue
        end

        --------------------------------------------------
        -- OTHER HTTP ERROR
        --------------------------------------------------

        local retryWait = math.min(
            attempt * 2,
            8
        )

        status.Text = string.format(
            "HTTP %d • retrying in %ds",
            tonumber(response.StatusCode) or 0,
            retryWait
        )

        task.wait(retryWait)
    end

    return nil, nil
end

--------------------------------------------------
--// SCAN
--------------------------------------------------

local function Scan()

    if Scanning then
        status.Text = "Already scanning..."
        return
    end

    if not stillValid() then
        return
    end

    Scanning = true
    StopScan = false

    local newServers = {}
    local seen = {}

    local cursor = ""
    local scanned = 0
    local failedPages = 0

    status.Text = "Scanning 0/" .. TARGET

    while scanned < TARGET
    and not StopScan
    and stillValid() do

        local data, nextCursor = getPage(cursor)

        --------------------------------------------------
        -- PAGE FAILED
        --------------------------------------------------

        if not data then

            failedPages += 1

            if failedPages <= 3
            and not StopScan
            and stillValid() then

                local recoveryWait =
                    failedPages * 4

                status.Text = string.format(
                    "Page failed • recovering %ds",
                    recoveryWait
                )

                task.wait(recoveryWait)

                continue
            end

            status.Text = string.format(
                "Scan stopped • %d/%d scanned",
                scanned,
                TARGET
            )

            break
        end

        failedPages = 0

        --------------------------------------------------
        -- PROCESS SERVERS
        --------------------------------------------------

        for _, server in ipairs(data) do

            if StopScan or not stillValid() then
                break
            end

            scanned += 1

            if server.id
            and not seen[server.id] then

                seen[server.id] = true

                local playing =
                    tonumber(server.playing) or 999

                if playing < MAX_PLAYERS then

                    table.insert(
                        newServers,
                        server
                    )

                end
            end

            status.Text = string.format(
                "Scanning %d/%d • %d available",
                scanned,
                TARGET,
                #newServers
            )

            if scanned >= TARGET then
                break
            end
        end

        if scanned >= TARGET
        or StopScan
        or not stillValid() then
            break
        end

        --------------------------------------------------
        -- NEXT PAGE
        --------------------------------------------------

        if not nextCursor
        or nextCursor == "" then

            status.Text = string.format(
                "No more pages • %d scanned",
                scanned
            )

            break
        end

        cursor = nextCursor

        -- IMPORTANT:
        -- No extra task.wait(DELAY) here.
        -- getPage() already controls request spacing.
    end

    --------------------------------------------------
    -- SAVE RESULTS
    --------------------------------------------------

    if stillValid() then

        if not StopScan and #newServers > 0 then

            Servers = newServers
            render()

        elseif StopScan then

            status.Text = string.format(
                "Scan stopped • %d old results",
                #Servers
            )

        else

            status.Text = string.format(
                "No usable servers • %d scanned",
                scanned
            )
        end
    end

    Scanning = false
end

--------------------------------------------------
--// BEST SERVER
--------------------------------------------------

local function getBestServer()

    if #Servers == 0 then
        return nil
    end

    local bestServer = nil
    local bestScore = math.huge

    for _, server in ipairs(Servers) do

        local players =
            tonumber(server.playing) or 999

        local ping =
            tonumber(server.ping)

        if not ping or ping <= 0 then
            ping = 999
        end

        --------------------------------------------------
        -- PLAYER PRIORITY
        --------------------------------------------------

        local score

        if players == 1 then

            score = 0

        elseif players == 2 then

            score = 100

        elseif players == 3 then

            score = 200

        elseif players == 4 then

            score = 300

        elseif players == 5 then

            score = 400

        elseif players == 6 then

            score = 500

        else

            score = 600
        end

        --------------------------------------------------
        -- 40-50MS PREFERRED
        --------------------------------------------------

        if ping >= 40 and ping <= 50 then

            score += ping - 40

        else

            score +=
                50 +
                math.abs(ping - 45)

        end

        --------------------------------------------------
        -- PING STILL MATTERS
        --------------------------------------------------

        score += ping * 0.5

        --------------------------------------------------
        -- BEST RESULT
        --------------------------------------------------

        if score < bestScore then

            bestScore = score
            bestServer = server

        end
    end

    return bestServer
end

--------------------------------------------------
--// RESCAN
--------------------------------------------------

scan.MouseButton1Click:Connect(function()

    if not stillValid() then
        return
    end

    if Scanning then

        status.Text = "Already scanning..."
        return
    end

    task.spawn(Scan)
end)

--------------------------------------------------
--// STOP
--------------------------------------------------

stop.MouseButton1Click:Connect(function()

    if Scanning then

        StopScan = true
        status.Text = "Stopping..."

    else

        status.Text = "No scan running"
    end
end)

--------------------------------------------------
--// BEST
--------------------------------------------------

bestButton.MouseButton1Click:Connect(function()

    local bestServer = getBestServer()

    if not bestServer then

        status.Text = "No servers available"
        return
    end

    local players =
        tonumber(bestServer.playing) or 0

    local ping =
        tonumber(bestServer.ping) or 0

    status.Text = string.format(
        "BEST: %d/%d • %dms",
        players,
        tonumber(bestServer.maxPlayers) or MAX_PLAYERS,
        ping
    )

    joinServer(bestServer.id)
end)

--------------------------------------------------
--// START
--------------------------------------------------

task.delay(1, function()

    if stillValid() then
        task.spawn(Scan)
    end

end)
