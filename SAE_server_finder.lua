--------------------------------------------------
--// ACTUAL PING CHECK
--------------------------------------------------

local TARGET_PING = 50
local MAX_ACCEPTABLE_PING = 60
local MAX_HOPS = 8

local function getActualPing()
    local success, ping = pcall(function()
        return Players.LocalPlayer:GetNetworkPing() * 1000
    end)

    if success and ping then
        return math.floor(ping + 0.5)
    end

    return nil
end


--------------------------------------------------
--// SORT CANDIDATES
--------------------------------------------------

local function getCandidates()

    local candidates = {}

    for _, server in ipairs(Servers) do

        local players =
            tonumber(server.playing) or 999

        local apiPing =
            tonumber(server.ping) or 999

        table.insert(candidates, {
            server = server,
            players = players,
            apiPing = apiPing
        })
    end

    -- Prefer fewer players first,
    -- then API ping only as a rough tie-breaker.
    table.sort(candidates, function(a, b)

        if a.players ~= b.players then
            return a.players < b.players
        end

        return a.apiPing < b.apiPing
    end)

    return candidates
end


--------------------------------------------------
--// JOIN + VERIFY REAL PING
--------------------------------------------------

local function findRealLowPingServer()

    if #Servers == 0 then
        status.Text = "No servers available"
        return
    end

    local candidates = getCandidates()

    local tried = {}
    local hops = 0

    for _, candidate in ipairs(candidates) do

        if hops >= MAX_HOPS then
            break
        end

        local server = candidate.server

        if not tried[server.id] then

            tried[server.id] = true
            hops += 1

            status.Text = string.format(
                "Trying server %d/%d • %d players",
                hops,
                MAX_HOPS,
                candidate.players
            )

            TeleportService:TeleportToPlaceInstance(
                PLACE_ID,
                server.id,
                LocalPlayer
            )

            -- Give the teleport enough time to complete.
            task.wait(8)

            local realPing = getActualPing()

            if realPing then

                status.Text = string.format(
                    "Actual ping: %dms",
                    realPing
                )

                -- Good server
                if realPing <= MAX_ACCEPTABLE_PING then

                    status.Text = string.format(
                        "FOUND • %d players • %dms",
                        #Players:GetPlayers(),
                        realPing
                    )

                    return
                end

                -- Bad server
                status.Text = string.format(
                    "Bad ping %dms • trying another",
                    realPing
                )

            else

                status.Text = "Could not measure ping"
            end
        end
    end

    local finalPing = getActualPing()

    if finalPing then

        status.Text = string.format(
            "Best found: %dms",
            finalPing
        )

    else

        status.Text = "Finished server search"
    end
end


--------------------------------------------------
--// BEST BUTTON
--------------------------------------------------

bestButton.MouseButton1Click:Connect(function()

    if Scanning then
        status.Text = "Wait for scan to finish"
        return
    end

    task.spawn(findRealLowPingServer)
end)
