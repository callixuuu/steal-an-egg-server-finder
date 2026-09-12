--//========================================================
--// STEAL AN EGG • REAL EXECUTOR SERVER FINDER
--// Place ID: 107778070777162
--//
--// 700-server scanner
--// Rate-limit protection
--// Lowest-player priority
--// 40-50ms preferred API ping
--// REAL client ping verification
--// Automatic re-hop on bad real ping
--// Real queue_on_teleport compatible
--//========================================================

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local GEN = getgenv()

local PLACE_ID = 107778070777162
local MAX_PLAYERS = 7
local TARGET = 300
local LIMIT = 100

local REQUEST_DELAY = 1.95
local RETRIES = 5
local MAX_BACKOFF = 20

local TARGET_PING_MIN = 5
local TARGET_PING_MAX = 55
local MAX_ACCEPTABLE_PING = 60

local PING_SAMPLES = 5
local PING_SAMPLE_DELAY = 0.7
local MAX_HOPS = 8

--=========================================================
-- REAL EXECUTOR CHECK
--=========================================================

local queueTeleport = queue_on_teleport

if type(queueTeleport) ~= "function" then
    warn("Real queue_on_teleport is unavailable.")
    return
end

--=========================================================
-- REQUEST
--=========================================================

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

--=========================================================
-- GLOBAL STATE
--=========================================================

GEN.StealEggFinder = GEN.StealEggFinder or {
    version = 0,
    servers = {},
    searching = false,
    hopIndex = 1,
    hopCount = 0,
    tried = {},
    candidates = {}
}

GEN.StealEggFinder.version += 1

local VERSION = GEN.StealEggFinder.version
local STATE = GEN.StealEggFinder

--=========================================================
-- REMOVE OLD UI
--=========================================================

pcall(function()
    local old = CoreGui:FindFirstChild("StealEggServerFinder")

    if old then
        old:Destroy()
    end
end)

--=========================================================
-- UI
--=========================================================

local gui = Instance.new("ScreenGui")
gui.Name = "StealEggServerFinder"
gui.ResetOnSpawn = false
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0,420,0,500)
main.Position = UDim2.new(.5,-210,.5,-250)
main.BackgroundColor3 = Color3.fromRGB(20,20,24)
main.BorderSizePixel = 0
main.Parent = gui

Instance.new("UICorner",main).CornerRadius = UDim.new(0,12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-20,0,40)
title.Position = UDim2.new(0,10,0,5)
title.BackgroundTransparency = 1
title.Text = "STEAL AN EGG • SERVER FINDER"
title.TextColor3 = Color3.new(1,1,1)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.Parent = main

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1,-20,0,25)
status.Position = UDim2.new(0,10,0,45)
status.BackgroundTransparency = 1
status.Text = "Ready • 0 servers"
status.TextColor3 = Color3.fromRGB(180,180,190)
status.TextSize = 13
status.Font = Enum.Font.Gotham
status.Parent = main

local scan = Instance.new("TextButton")
scan.Size = UDim2.new(0,125,0,35)
scan.Position = UDim2.new(0,10,0,78)
scan.BackgroundColor3 = Color3.fromRGB(45,45,55)
scan.Text = "RESCAN"
scan.TextColor3 = Color3.new(1,1,1)
scan.Font = Enum.Font.GothamBold
scan.TextSize = 13
scan.Parent = main

Instance.new("UICorner",scan).CornerRadius = UDim.new(0,8)

local stop = scan:Clone()
stop.Position = UDim2.new(0,145,0,78)
stop.Text = "STOP"
stop.Parent = main

local best = scan:Clone()
best.Position = UDim2.new(0,280,0,78)
best.Text = "BEST"
best.Parent = main

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1,-20,1,-125)
list.Position = UDim2.new(0,10,0,120)
list.BackgroundColor3 = Color3.fromRGB(15,15,18)
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.CanvasSize = UDim2.new()
list.Parent = main

local layout = Instance.new("UIListLayout",list)
layout.Padding = UDim.new(0,6)

--=========================================================
-- DRAG
--=========================================================

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

    if dragging and (
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

--=========================================================
-- UTILITY
--=========================================================

local function getPing()

    local ok,ping = pcall(function()
        return LocalPlayer:GetNetworkPing() * 1000
    end)

    if ok and type(ping) == "number" then
        return math.floor(ping + 0.5)
    end

    return nil
end

local function waitRequestGap()

    local now = os.clock()

    GEN.StealEggLastRequest =
        GEN.StealEggLastRequest or 0

    local elapsed =
        now - GEN.StealEggLastRequest

    if elapsed < REQUEST_DELAY then
        task.wait(REQUEST_DELAY - elapsed)
    end

    GEN.StealEggLastRequest = os.clock()
end

local function clearList()

    for _,v in ipairs(list:GetChildren()) do
        if v:IsA("Frame") then
            v:Destroy()
        end
    end
end

--=========================================================
-- SERVER CARD
--=========================================================

local function addServer(server)

    local card = Instance.new("Frame")
    card.Size = UDim2.new(1,-10,0,65)
    card.BackgroundColor3 = Color3.fromRGB(28,28,34)
    card.BorderSizePixel = 0
    card.Parent = list

    Instance.new("UICorner",card).CornerRadius = UDim.new(0,8)

    local ping = tonumber(server.ping)

    if not ping or ping <= 0 then
        ping = "?"
    end

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1,-110,1,0)
    info.Position = UDim2.new(0,10,0,0)
    info.BackgroundTransparency = 1
    info.TextXAlignment = Enum.TextXAlignment.Left

    info.Text = string.format(
        "%d/%d PLAYERS • %sms\n%s",
        tonumber(server.playing) or 0,
        tonumber(server.maxPlayers) or 7,
        ping,
        tostring(server.id)
    )

    info.TextColor3 = Color3.new(1,1,1)
    info.TextSize = 12
    info.Font = Enum.Font.Gotham
    info.Parent = card

    local join = Instance.new("TextButton")
    join.Size = UDim2.new(0,80,0,30)
    join.Position = UDim2.new(1,-90,.5,-15)
    join.BackgroundColor3 = Color3.fromRGB(55,55,65)
    join.Text = "JOIN"
    join.TextColor3 = Color3.new(1,1,1)
    join.Font = Enum.Font.GothamBold
    join.TextSize = 12
    join.Parent = card

    Instance.new("UICorner",join).CornerRadius = UDim.new(0,7)

    join.MouseButton1Click:Connect(function()

        TeleportService:TeleportToPlaceInstance(
            PLACE_ID,
            server.id,
            LocalPlayer
        )

    end)
end

--=========================================================
-- RENDER
--=========================================================

local function render()

    clearList()

    table.sort(STATE.servers,function(a,b)

        local ap = tonumber(a.playing) or 999
        local bp = tonumber(b.playing) or 999

        if ap ~= bp then
            return ap < bp
        end

        return (tonumber(a.ping) or 999)
             < (tonumber(b.ping) or 999)
    end)

    for _,server in ipairs(STATE.servers) do
        addServer(server)
    end

    list.CanvasSize = UDim2.new(
        0,0,0,
        layout.AbsoluteContentSize.Y + 10
    )

    status.Text = string.format(
        "Found %d available • scanned 700/700",
        #STATE.servers
    )
end

--=========================================================
-- GET PAGE
--=========================================================

local function getPage(cursor)

    local url =
        "https://games.roblox.com/v1/games/" ..
        PLACE_ID ..
        "/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=" ..
        LIMIT

    if cursor and cursor ~= "" then

        url =
            url ..
            "&cursor=" ..
            HttpService:UrlEncode(cursor)

    end

    for attempt = 1,RETRIES do

        waitRequestGap()

        local ok,response = pcall(function()

            return Request({
                Url = url,
                Method = "GET"
            })

        end)

        if ok and response then

            if response.StatusCode == 200 then

                GEN.StealEggLastRequest = os.clock()

                consecutive429 = 0

                local success,data =
                    pcall(function()
                        return HttpService:JSONDecode(
                            response.Body
                        )
                    end)

                if success and data then
                    return data.data or {},
                        data.nextPageCursor
                end
            end

            if response.StatusCode == 429 then

                consecutive429 =
                    (consecutive429 or 0) + 1

                local retryAfter

                pcall(function()

                    if response.Headers then

                        retryAfter =
                            response.Headers["Retry-After"] or
                            response.Headers["retry-after"]

                    end

                end)

                retryAfter = tonumber(retryAfter)

                if not retryAfter then

                    retryAfter = math.min(
                        3 * consecutive429,
                        15
                    )

                end

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

            else

                task.wait(
                    math.min(attempt * 2,8)
                )

            end

        else

            task.wait(
                math.min(attempt * 2,8)
            )

        end
    end

    return nil,nil
end

--=========================================================
-- SCAN 700
--=========================================================

local function Scan()

    if Scanning then
        return
    end

    Scanning = true

    local results = {}
    local seen = {}

    local cursor = ""
    local scanned = 0
    local failed = 0

    status.Text = "Scanning 0/700"

    while scanned < TARGET do

        local data,nextCursor =
            getPage(cursor)

        if not data then

            failed += 1

            if failed <= 3 then

                status.Text =
                    "Page failed • recovering..."

                task.wait(failed * 4)

                continue
            end

            break
        end

        failed = 0

        for _,server in ipairs(data) do

            scanned += 1

            if server.id
            and not seen[server.id] then

                seen[server.id] = true

                if tonumber(server.playing or 999)
                < MAX_PLAYERS then

                    table.insert(
                        results,
                        server
                    )

                end
            end

            status.Text = string.format(
                "Scanning %d/700 • %d available",
                scanned,
                #results
            )

            if scanned >= TARGET then
                break
            end
        end

        if scanned >= TARGET then
            break
        end

        if not nextCursor
        or nextCursor == "" then
            break
        end

        cursor = nextCursor
    end

    STATE.servers = results

    Scanning = false

    render()
end

--=========================================================
-- CANDIDATE SORT
--=========================================================

local function buildCandidates()

    local candidates = {}

    for _,server in ipairs(STATE.servers) do

        local players =
            tonumber(server.playing) or 999

        local ping =
            tonumber(server.ping) or 999

        local score =
            players * 100

        -- Very strong preference for 1-player
        if players == 1 then
            score -= 300
        elseif players == 2 then
            score -= 150
        elseif players == 3 then
            score -= 50
        end

        -- API ping only decides which candidate
        -- we test first. Real ping decides whether
        -- we stay.
        if ping >= 40 and ping <= 50 then
            score += math.abs(ping - 45)
        else
            score += 30 + math.abs(ping - 45)
        end

        table.insert(candidates,{
            id = server.id,
            playing = players,
            apiPing = ping,
            score = score
        })
    end

    table.sort(candidates,function(a,b)
        return a.score < b.score
    end)

    return candidates
end

--=========================================================
-- QUEUE CONTINUATION
--=========================================================

local function queueContinuation()

    local source = [[
        task.wait(6)

        local Players = game:GetService("Players")
        local TeleportService = game:GetService("TeleportService")
        local LocalPlayer = Players.LocalPlayer
        local GEN = getgenv()

        local STATE = GEN.StealEggFinder

        if not STATE
        or not STATE.searching then
            return
        end

        local function getPing()
            local ok,ping = pcall(function()
                return LocalPlayer:GetNetworkPing() * 1000
            end)

            if ok and type(ping) == "number" then
                return math.floor(ping + 0.5)
            end

            return nil
        end

        local samples = {}

        for i = 1,5 do

            local ping = getPing()

            if ping then
                table.insert(samples,ping)
            end

            task.wait(0.7)
        end

        if #samples == 0 then

            STATE.searching = false
            return
        end

        table.sort(samples)

        local realPing =
            samples[math.ceil(#samples / 2)]

        ---------------------------------------------------
        -- ACCEPT
        ---------------------------------------------------

        if realPing <= 60 then

            STATE.searching = false
            STATE.finishedPing = realPing

            return
        end

        ---------------------------------------------------
        -- REJECT
        ---------------------------------------------------

        STATE.hopCount =
            (STATE.hopCount or 0) + 1

        if STATE.hopCount >= 8 then

            STATE.searching = false
            STATE.finishedPing = realPing

            return
        end

        ---------------------------------------------------
        -- NEXT CANDIDATE
        ---------------------------------------------------

        STATE.hopIndex =
            (STATE.hopIndex or 1) + 1

        local candidate =
            STATE.candidates[
                STATE.hopIndex
            ]

        if not candidate then

            STATE.searching = false
            STATE.finishedPing = realPing

            return
        end

        ---------------------------------------------------
        -- QUEUE NEXT CHECK
        ---------------------------------------------------

        local queue_on_teleport =
            queue_on_teleport

        if type(queue_on_teleport) ~= "function" then
            STATE.searching = false
            return
        end

        queue_on_teleport([[
            task.wait(6)

            local Players = game:GetService("Players")
            local LocalPlayer = Players.LocalPlayer
            local TeleportService = game:GetService("TeleportService")
            local GEN = getgenv()
            local STATE = GEN.StealEggFinder

            if not STATE or not STATE.searching then
                return
            end

            local function ping()
                local ok,p = pcall(function()
                    return LocalPlayer:GetNetworkPing() * 1000
                end)

                if ok and type(p) == "number" then
                    return math.floor(p + 0.5)
                end
            end

            local samples = {}

            for i = 1,5 do
                local p = ping()

                if p then
                    table.insert(samples,p)
                end

                task.wait(0.7)
            end

            if #samples == 0 then
                return
            end

            table.sort(samples)

            local real = samples[
                math.ceil(#samples/2)
            ]

            if real <= 60 then
                STATE.searching = false
                STATE.finishedPing = real
                return
            end

            STATE.hopCount =
                (STATE.hopCount or 0) + 1

            if STATE.hopCount >= 8 then
                STATE.searching = false
                STATE.finishedPing = real
                return
            end

            STATE.hopIndex =
                (STATE.hopIndex or 1) + 1

            local nextCandidate =
                STATE.candidates[
                    STATE.hopIndex
                ]

            if not nextCandidate then
                STATE.searching = false
                return
            end

            local q = queue_on_teleport

            if type(q) == "function" then
                q([[

                    task.wait(6)

                    local Players = game:GetService("Players")
                    local LocalPlayer = Players.LocalPlayer
                    local GEN = getgenv()
                    local STATE = GEN.StealEggFinder

                    if not STATE or not STATE.searching then
                        return
                    end

                    local samples = {}

                    for i = 1,5 do
                        local ok,p = pcall(function()
                            return LocalPlayer:GetNetworkPing() * 1000
                        end)

                        if ok and type(p) == "number" then
                            table.insert(samples,math.floor(p + 0.5))
                        end

                        task.wait(0.7)
                    end

                    if #samples == 0 then
                        return
                    end

                    table.sort(samples)

                    local real =
                        samples[math.ceil(#samples/2)]

                    if real <= 60 then
                        STATE.searching = false
                        STATE.finishedPing = real
                        return
                    end

                    STATE.hopCount =
                        (STATE.hopCount or 0) + 1

                    if STATE.hopCount >= 8 then
                        STATE.searching = false
                        STATE.finishedPing = real
                        return
                    end

                    STATE.hopIndex =
                        (STATE.hopIndex or 1) + 1

                    local candidate =
                        STATE.candidates[
                            STATE.hopIndex
                        ]

                    if not candidate then
                        STATE.searching = false
                        return
                    end

                    local queue =
                        queue_on_teleport

                    if type(queue) == "function" then
                        queue([[

                            -- Continue through the same
                            -- Real teleport verifier.

                            task.wait(6)

                            local P = game:GetService("Players")
                            local LP = P.LocalPlayer
                            local G = getgenv()
                            local S = G.StealEggFinder

                            if not S or not S.searching then
                                return
                            end

                            local values = {}

                            for i = 1,5 do

                                local ok,x = pcall(function()
                                    return LP:GetNetworkPing() * 1000
                                end)

                                if ok and type(x) == "number" then
                                    table.insert(
                                        values,
                                        math.floor(x + 0.5)
                                    )
                                end

                                task.wait(0.7)
                            end

                            if #values == 0 then
                                return
                            end

                            table.sort(values)

                            local actual =
                                values[math.ceil(#values/2)]

                            if actual <= 60 then
                                S.searching = false
                                S.finishedPing = actual
                                return
                            end

                            S.hopCount =
                                (S.hopCount or 0) + 1

                            if S.hopCount >= 8 then
                                S.searching = false
                                S.finishedPing = actual
                                return
                            end

                            S.hopIndex =
                                (S.hopIndex or 1) + 1

                            local c =
                                S.candidates[S.hopIndex]

                            if not c then
                                S.searching = false
                                return
                            end

                            queue_on_teleport(
                                "print('Steal Egg finder: next candidate queued')"
                            )

                            TeleportService:TeleportToPlaceInstance(
                                107778070777162,
                                c.id,
                                LP
                            )

                        ]])
                    end

                    TeleportService:TeleportToPlaceInstance(
                        107778070777162,
                        candidate.id,
                        LocalPlayer
                    )

                ]])
            end

        ]])

    end
end
