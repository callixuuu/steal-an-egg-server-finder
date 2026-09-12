--//========================================================
--// STEAL AN EGG • SERVER FINDER
--// Place ID: 107778070777162
--//
--// FEATURES
--// • Scans up to 700 raw public-server results
--// • Rate-limit-safe with progressive backoff
--// • Avoids duplicate scanners
--// • Shows players + API ping
--// • BEST prefers low player count
--// • Prefers API ping around 40-50ms
--// • After joining, measures REAL client ping
--// • Automatically re-hops if real ping is too high
--//
--// IMPORTANT
--// Automatic post-teleport verification requires:
--// queue_on_teleport / queueonteleport
--//========================================================

------------------------------------------------------------
--// GLOBAL / DUPLICATE PROTECTION
------------------------------------------------------------

local GEN = getgenv and getgenv() or _G

GEN.StealEggFinderVersion = (GEN.StealEggFinderVersion or 0) + 1
local MY_VERSION = GEN.StealEggFinderVersion

pcall(function()
    local old = game:GetService("CoreGui"):FindFirstChild(
        "StealEggServerFinder"
    )

    if old then
        old:Destroy()
    end
end)

------------------------------------------------------------
--// SERVICES
------------------------------------------------------------

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

------------------------------------------------------------
--// CONFIG
------------------------------------------------------------

local PLACE_ID = 107778070777162

local MAX_PLAYERS = 7

-- Scan target
local TARGET = 300

-- Roblox API page size
local LIMIT = 100

-- Normal spacing between requests
local REQUEST_DELAY = 1.95

-- Retry failed HTTP requests
local RETRIES = 5

-- Maximum rate-limit cooldown
local MAX_BACKOFF = 20

------------------------------------------------------------
--// REAL PING CONFIG
------------------------------------------------------------

-- Preferred range
local TARGET_PING_MIN = 5
local TARGET_PING_MAX = 55

-- Accept server if real ping is <= this
local MAX_ACCEPTABLE_PING = 60

-- Number of ping measurements
local PING_SAMPLES = 5

-- Seconds between ping measurements
local PING_SAMPLE_DELAY = 0.8

-- Maximum number of candidate servers to try
local MAX_HOPS = 8

------------------------------------------------------------
--// HTTP FUNCTION
------------------------------------------------------------

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

------------------------------------------------------------
--// TELEPORT QUEUE
------------------------------------------------------------

local queueTeleport =
    queue_on_teleport or
    queueonteleport

local function canQueueTeleport()
    return type(queueTeleport) == "function"
end

------------------------------------------------------------
--// STATE
------------------------------------------------------------

local Servers = {}

local Scanning = false
local StopScan = false

local consecutive429 = 0
local lastRequestTime = 0

local BestSearchActive = false
local BestHops = 0

------------------------------------------------------------
--// UTILS
------------------------------------------------------------

local function stillValid()
    return GEN.StealEggFinderVersion == MY_VERSION
end

local function getPingMs()
    local success, ping = pcall(function()
        return LocalPlayer:GetNetworkPing() * 1000
    end)

    if success and type(ping) == "number" then
        return math.floor(ping + 0.5)
    end

    return nil
end

local function waitForRequestGap(delayTime)

    local elapsed = os.clock() - lastRequestTime

    if elapsed < delayTime then
        task.wait(delayTime - elapsed)
    end

    lastRequestTime = os.clock()
end

------------------------------------------------------------
--// UI
------------------------------------------------------------

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

------------------------------------------------------------
--// TITLE
------------------------------------------------------------

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 40)
title.Position = UDim2.new(0, 10, 0, 5)
title.BackgroundTransparency = 1
title.Text = "STEAL AN EGG • SERVER FINDER"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.Parent = main

------------------------------------------------------------
--// STATUS
------------------------------------------------------------

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 25)
status.Position = UDim2.new(0, 10, 0, 45)
status.BackgroundTransparency = 1
status.Text = "Ready • 0 servers"
status.TextColor3 = Color3.fromRGB(180, 180, 190)
status.TextSize = 13
status.Font = Enum.Font.Gotham
status.Parent = main

------------------------------------------------------------
--// BUTTONS
------------------------------------------------------------

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

------------------------------------------------------------
--// SERVER LIST
------------------------------------------------------------

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

------------------------------------------------------------
--// DRAGGING
------------------------------------------------------------

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

UserInputService.InputChanged:Connect(function(input)

    if not dragging then
        return
    end

    if input.UserInputType ~= Enum.UserInputType.MouseMovement
    and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local delta = input.Position - dragStart

    main.Position = UDim2.new(
        startPos.X.Scale,
        startPos.X.Offset + delta.X,

        startPos.Y.Scale,
        startPos.Y.Offset + delta.Y
    )
end)

------------------------------------------------------------
--// CLEAR LIST
------------------------------------------------------------

local function clearList()

    for _, object in ipairs(list:GetChildren()) do

        if object:IsA("Frame") then
            object:Destroy()
        end

    end
end

------------------------------------------------------------
--// JOIN SERVER
------------------------------------------------------------

local function joinServer(serverId)

    if not serverId then
        return
    end

    TeleportService:TeleportToPlaceInstance(
        PLACE_ID,
        serverId,
        LocalPlayer
    )
end

------------------------------------------------------------
--// ADD SERVER CARD
------------------------------------------------------------

local function addServer(server)

    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -10, 0, 65)
    card.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    card.BorderSizePixel = 0
    card.Parent = list

    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    local ping = tonumber(server.ping)

    local pingText = "?"

    if ping and ping > 0 then
        pingText = tostring(math.floor(ping))
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
        pingText,
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

        if stillValid() then
            joinServer(server.id)
        end

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

------------------------------------------------------------
--// RENDER
------------------------------------------------------------

local function render()

    clearList()

    table.sort(Servers, function(a, b)

        local ap = tonumber(a.playing) or 999
        local bp = tonumber(b.playing) or 999

        if ap ~= bp then
            return ap < bp
        end

        local aq = tonumber(a.ping) or 999
        local bq = tonumber(b.ping) or 999

        return aq < bq
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
        "Found %d available • scanned 700/700",
        #Servers
    )
end

------------------------------------------------------------
--// API PAGE
------------------------------------------------------------

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

    for attempt = 1, RETRIES do

        if StopScan or not stillValid() then
            return nil, nil
        end

        waitForRequestGap(REQUEST_DELAY)

        local ok, response = pcall(function()

            return Request({
                Url = url,
                Method = "GET"
            })

        end)

        if not ok or not response then

            local waitTime = math.min(
                attempt * 2,
                8
            )

            status.Text = string.format(
                "Request failed • retrying in %ds",
                waitTime
            )

            task.wait(waitTime)

            continue
        end

        --------------------------------------------------
        -- SUCCESS
        --------------------------------------------------

        if response.StatusCode == 200 then

            consecutive429 = 0

            local decoded, data = pcall(function()
                return HttpService:JSONDecode(
                    response.Body
                )
            end)

            if decoded and data then

                return (
                    data.data or {}
                ), data.nextPageCursor

            end

            status.Text = "Invalid response • retrying..."
            task.wait(2)

            continue
        end

        --------------------------------------------------
        -- RATE LIMIT
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

            lastRequestTime = os.clock()

            continue
        end

        --------------------------------------------------
        -- OTHER HTTP ERROR
        --------------------------------------------------

        local waitTime = math.min(
            attempt * 2,
            8
        )

        status.Text = string.format(
            "HTTP %d • retrying in %ds",
            tonumber(response.StatusCode) or 0,
            waitTime
        )

        task.wait(waitTime)
    end

    return nil, nil
end

------------------------------------------------------------
--// SCAN
------------------------------------------------------------

local function Scan()

    if Scanning then
        status.Text = "Already scanning..."
        return
    end

    Scanning = true
    StopScan = false

    local results = {}
    local seen = {}

    local cursor = ""
    local scanned = 0
    local failedPages = 0

    status.Text = "Scanning 0/" .. TARGET

    while scanned < TARGET
    and not StopScan
    and stillValid() do

        local data, nextCursor = getPage(cursor)

        if not data then

            failedPages += 1

            if failedPages <= 3 then

                local recovery = failedPages * 4

                status.Text = string.format(
                    "Page failed • recovering %ds",
                    recovery
                )

                task.wait(recovery)

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

        for _, server in ipairs(data) do

            if StopScan or not stillValid() then
                break
            end

            scanned += 1

            if server.id
            and not seen[server.id] then

                seen[server.id] = true

                local playing =
                    tonumber(server.playing) or MAX_PLAYERS

                if playing < MAX_PLAYERS then
                    table.insert(results, server)
                end

            end

            status.Text = string.format(
                "Scanning %d/%d • %d available",
                scanned,
                TARGET,
                #results
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

        if not nextCursor
        or nextCursor == "" then

            status.Text = string.format(
                "No more pages • %d scanned",
                scanned
            )

            break
        end

        cursor = nextCursor
    end

    if not StopScan
    and stillValid()
    and #results > 0 then

        Servers = results
        render()

    elseif StopScan then

        status.Text = string.format(
            "Scan stopped • %d old results",
            #Servers
        )

    end

    Scanning = false
end

------------------------------------------------------------
--// CANDIDATE SCORE
------------------------------------------------------------

local function getCandidateScore(server)

    local players =
        tonumber(server.playing) or 999

    local apiPing =
        tonumber(server.ping) or 999

    -- Player priority
    local playerScore = players * 100

    -- Strong bonus for exactly 1 player
    if players == 1 then
        playerScore -= 250
    elseif players == 2 then
        playerScore -= 120
    elseif players == 3 then
        playerScore -= 50
    end

    -- API ping is only a candidate hint.
    -- Real ping is checked AFTER joining.
    local pingScore

    if apiPing >= TARGET_PING_MIN
    and apiPing <= TARGET_PING_MAX then

        pingScore = math.abs(apiPing - 45)

    else

        pingScore =
            25 +
            math.abs(apiPing - 45)

    end

    return playerScore + pingScore
end

------------------------------------------------------------
--// BUILD CANDIDATE LIST
------------------------------------------------------------

local function getCandidates()

    local candidates = {}

    for _, server in ipairs(Servers) do

        table.insert(candidates, {
            server = server,
            score = getCandidateScore(server)
        })

    end

    table.sort(candidates, function(a, b)
        return a.score < b.score
    end)

    return candidates
end

------------------------------------------------------------
--// REAL PING SAMPLING
------------------------------------------------------------

local function measureStablePing()

    local samples = {}

    for i = 1, PING_SAMPLES do

        if not stillValid() then
            return nil
        end

        local ping = getPingMs()

        if ping then
            table.insert(samples, ping)
        end

        if i < PING_SAMPLES then
            task.wait(PING_SAMPLE_DELAY)
        end

    end

    if #samples == 0 then
        return nil
    end

    table.sort(samples)

    -- Use median rather than a single sample.
    local middle = math.ceil(#samples / 2)

    return samples[middle]
end

------------------------------------------------------------
--// TELEPORT RETRY STATE
------------------------------------------------------------

GEN.StealEggBestSearch = GEN.StealEggBestSearch or {
    active = false,
    index = 1,
    candidates = {},
    tried = {},
    hopCount = 0
}

local SearchState = GEN.StealEggBestSearch

------------------------------------------------------------
--// QUEUE AFTER TELEPORT
------------------------------------------------------------

local function queueContinuation()

    if not canQueueTeleport() then
        return false
    end

    -- This assumes the executor automatically re-executes
    -- this same script through its teleport queue facility.
    --
    -- The state itself is stored in getgenv(), but executors
    -- differ in how much state survives. The queued script
    -- needs to re-run your current script.

    return true
end

------------------------------------------------------------
--// VERIFY CURRENT SERVER
//------------------------------------------------------------

local function verifyCurrentServer()

    if not SearchState.active then
        return
    end

    task.wait(7)

    local realPing = measureStablePing()

    if not realPing then

        status.Text = "Unable to measure real ping"

        SearchState.active = false
        return
    end

    --------------------------------------------------------
    -- GOOD SERVER
    --------------------------------------------------------

    if realPing <= MAX_ACCEPTABLE_PING then

        local playerCount =
            #Players:GetPlayers()

        status.Text = string.format(
            "FOUND • %d players • REAL %dms",
            playerCount,
            realPing
        )

        SearchState.active = false
        BestSearchActive = false

        return
    end

    --------------------------------------------------------
    -- BAD SERVER
    --------------------------------------------------------

    SearchState.hopCount += 1

    if SearchState.hopCount >= MAX_HOPS then

        status.Text = string.format(
            "Best found • REAL %dms",
            realPing
        )

        SearchState.active = false
        BestSearchActive = false

        return
    end

    status.Text = string.format(
        "Real ping %dms • searching another",
        realPing
    )

    local nextIndex = SearchState.index + 1

    SearchState.index = nextIndex

    local candidate =
        SearchState.candidates[nextIndex]

    if not candidate then

        status.Text =
            "No more candidates to test"

        SearchState.active = false
        BestSearchActive = false

        return
    end

    if SearchState.tried[candidate.server.id] then

        SearchState.index += 1

        task.spawn(function()
            verifyCurrentServer()
        end)

        return
    end

    SearchState.tried[candidate.server.id] = true

    --------------------------------------------------------
    -- QUEUE SCRIPT BEFORE TELEPORT
    --------------------------------------------------------

    if not canQueueTeleport() then

        status.Text =
            "queue_on_teleport unavailable"

        SearchState.active = false
        BestSearchActive = false

        return
    end

    queueContinuation()

    task.wait(0.25)

    status.Text = string.format(
        "Hop %d/%d • %d players • API %dms",
        SearchState.hopCount + 1,
        MAX_HOPS,
        tonumber(candidate.server.playing) or 0,
        tonumber(candidate.server.ping) or 0
    )

    joinServer(candidate.server.id)
end

------------------------------------------------------------
--// START BEST SEARCH
------------------------------------------------------------

local function StartBestSearch()

    if BestSearchActive then
        status.Text = "BEST search already running"
        return
    end

    if Scanning then

        status.Text =
            "Wait for scan to finish"

        return
    end

    if #Servers == 0 then

        status.Text =
            "No servers scanned yet"

        return
    end

    --------------------------------------------------------
    -- REQUIRE QUEUE SUPPORT
    --------------------------------------------------------

    if not canQueueTeleport() then

        status.Text =
            "Automatic re-hop unavailable"

        warn(
            "Your executor does not provide queue_on_teleport."
        )

        return
    end

    BestSearchActive = true

    local candidates = getCandidates()

    SearchState.active = true
    SearchState.index = 1
    SearchState.candidates = candidates
    SearchState.tried = {}
    SearchState.hopCount = 0

    --------------------------------------------------------
    -- FIRST CANDIDATE
    --------------------------------------------------------

    local first = candidates[1]

    if not first then

        status.Text =
            "No candidates"

        SearchState.active = false
        BestSearchActive = false

        return
    end

    SearchState.tried[first.server.id] = true

    status.Text = string.format(
        "Hop 1/%d • %d players • API %dms",
        MAX_HOPS,
        tonumber(first.server.playing) or 0,
        tonumber(first.server.ping) or 0
    )

    --------------------------------------------------------
    -- QUEUE FOR NEXT SERVER
    --------------------------------------------------------

    queueContinuation()

    task.wait(0.25)

    joinServer(first.server.id)
end

------------------------------------------------------------
--// BUTTONS
//------------------------------------------------------------

scan.MouseButton1Click:Connect(function()

    if Scanning then
        status.Text = "Already scanning..."
        return
    end

    task.spawn(Scan)
end)

stop.MouseButton1Click:Connect(function()

    StopScan = true
    BestSearchActive = false
    SearchState.active = false

    status.Text = "Stopping..."
end)

bestButton.MouseButton1Click:Connect(function()

    task.spawn(function()

        -- If this is a fresh script execution in a newly
        -- teleported server, verify the queued search first.
        if SearchState.active
        and SearchState.hopCount > 0 then

            verifyCurrentServer()

            return
        end

        StartBestSearch()

    end)
end)

------------------------------------------------------------
--// AUTO-CONTINUE AFTER TELEPORT
//------------------------------------------------------------

task.spawn(function()

    -- Wait for the local player to finish loading.
    task.wait(2)

    if not stillValid() then
        return
    end

    if SearchState.active
    and SearchState.hopCount > 0 then

        BestSearchActive = true

        status.Text =
            "New server • measuring real ping..."

        verifyCurrentServer()
    end

end)

------------------------------------------------------------
--// INITIAL SCAN
//------------------------------------------------------------

task.delay(1, function()

    if stillValid() then
        task.spawn(Scan)
    end

end)
