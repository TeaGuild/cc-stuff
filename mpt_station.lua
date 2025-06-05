-- Multi-Platform Train Station Controller with Graphics
-- Supports multiple station peripherals on one computer with visual display
-- Version 2.0 - Uses improved manifest format with platform-based organization

-- Configuration
local SERVER_URL = "https://ryusei.bun-procyon.ts.net"
local GITHUB_USER = "TeaGuild"
local GITHUB_REPO = "cc-stuff"
local GITHUB_BRANCH = "master"
local MANIFEST_FILE = "station_manifest.json"
local UPDATE_INTERVAL = 2
local MANIFEST_UPDATE_INTERVAL = 300  -- 5 minutes

-- Get computer ID
local COMPUTER_ID = os.getComputerID()

-- Find all station peripherals
local stations = {}
local STATION_IDS = {}  -- Format: "computerID:peripheralName"

-- More robust station detection
local peripherals = peripheral.getNames()
for _, name in ipairs(peripherals) do
    local pType = peripheral.getType(name)
    if pType and (
        string.find(string.lower(pType), "station") or
        string.find(string.lower(pType), "create") and string.find(string.lower(pType), "station") or
        pType == "create:station" or
        pType == "createstation" or
        pType == "Create_Station"
    ) then
        local test = peripheral.wrap(name)
        if test and pcall(test.getStationName) then
            local stationId = COMPUTER_ID .. ":" .. name
            stations[stationId] = test
            table.insert(STATION_IDS, stationId)
            print("Found station: " .. stationId)
        end
    end
end

if #STATION_IDS == 0 then
    error("No Create train stations found!")
end

-- Find peripherals
local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
local useMonitor = monitor ~= nil
local useSpeaker = speaker ~= nil

-- Monitor setup
if useMonitor then
    monitor.setTextScale(0.5)  -- Smaller text for more info
    monitor.clear()
end

-- Global state
local manifest = nil
local stationData = {}  -- Keyed by station ID
local platformInfo = {}  -- Manifest data per station ID
local lastManifestUpdate = 0
local soundEnabled = true
local lastSoundTime = {}  -- Per station ID
local showLatinNames = true  -- Toggle for name display

-- Colors for lines (ComputerCraft colors)
local LINE_COLORS = {
    K = colors.green,
    P = colors.orange,
    CM = colors.red,
    default = colors.gray
}

-- Direction symbols
local DIRECTION_SYMBOLS = {
    north = "↑",
    south = "↓",
    east = "→",
    west = "←"
}

-- Helper functions
local function safeCall(func, ...)
    local success, result = pcall(func, ...)
    if success then
        return result
    else
        return nil
    end
end

-- Sound functions
local function playTone(frequency, duration, volume)
    if not useSpeaker or not soundEnabled then return end
    
    volume = volume or 0.3
    local sampleRate = 48000
    local samples = math.floor(sampleRate * duration)
    local buffer = {}
    
    for i = 1, samples do
        local t = (i - 1) / sampleRate
        local value = math.sin(2 * math.pi * frequency * t) * 127 * volume
        buffer[i] = math.floor(value)
    end
    
    speaker.playAudio(buffer)
end

local function playStationSound(soundType, stationId)
    if not useSpeaker or not soundEnabled then return end
    
    -- Check cooldown per station
    local currentTime = os.clock()
    if lastSoundTime[stationId] and (currentTime - lastSoundTime[stationId] < 10) then
        return
    end
    
    if soundType == "arrival" then
        -- Pleasant arrival chime
        playTone(659, 0.2, 0.3)  -- E5
        playTone(523, 0.2, 0.3)  -- C5
        playTone(392, 0.4, 0.3)  -- G4
        
    elseif soundType == "departure" then
        -- Departure whistle
        playTone(440, 0.5, 0.4)  -- A4
        sleep(0.1)
        playTone(440, 0.3, 0.4)  -- A4
        
    elseif soundType == "imminent" then
        -- Warning beeps
        for i = 1, 2 do
            playTone(523, 0.1, 0.3)  -- C5
            playTone(659, 0.1, 0.3)  -- E5
            sleep(0.05)
        end
    end
    
    lastSoundTime[stationId] = currentTime
end

-- Download manifest from GitHub
local function downloadManifest()
    local url = string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s",
        GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, MANIFEST_FILE
    )
    
    local response = http.get(url)
    if not response then
        return nil, "Failed to download manifest"
    end
    
    local content = response.readAll()
    response.close()
    
    local manifest = textutils.unserialiseJSON(content)
    if not manifest then
        return nil, "Failed to parse manifest"
    end
    
    return manifest, nil
end

-- Process manifest to create platform lookup
local function processManifest(manifest)
    platformInfo = {}
    
    for stationName, station in pairs(manifest.stations) do
        for platformId, platform in pairs(station.platforms) do
            platformInfo[platformId] = {
                station_name = station.name,
                station_name_latin = station.name_latin,
                station_name_en = station.name_en,
                line = platform.line,
                direction = platform.direction,
                next_station = platform.next_station,
                platform_name = platform.platform_name,
                is_transfer = station.transfer,
                connections = {}
            }
            
            -- Build connections list
            for _, line in ipairs(station.lines) do
                if line ~= platform.line then
                    table.insert(platformInfo[platformId].connections, line)
                end
            end
        end
    end
end

-- Gather data from a station peripheral
local function getStationData(station, stationId)
    local data = {
        station_id = stationId,
        computer_id = COMPUTER_ID,
        peripheral_name = stationId:match(":(.+)"),
        assembly_mode = safeCall(station.isInAssemblyMode) or false,
        train_present = safeCall(station.isTrainPresent) or false,
        train_imminent = safeCall(station.isTrainImminent) or false,
        train_enroute = safeCall(station.isTrainEnroute) or false,
        station_name = safeCall(station.getStationName) or "Unknown"
    }
    
    if data.train_present then
        data.train_name = safeCall(station.getTrainName)
        data.has_schedule = safeCall(station.hasSchedule) or false
    end
    
    -- Add platform info from manifest
    if platformInfo[stationId] then
        local pInfo = platformInfo[stationId]
        data.line = pInfo.line
        data.manifest_name = showLatinNames and pInfo.station_name_latin or pInfo.station_name_en
        data.direction = pInfo.direction
        data.next_station = pInfo.next_station
        data.platform_name = pInfo.platform_name
        data.is_transfer = pInfo.is_transfer
        data.connections = pInfo.connections
    end
    
    return data
end

-- Send update to server
local function sendUpdate(data)
    local json = textutils.serialiseJSON(data)
    local headers = {["Content-Type"] = "application/json"}
    
    local response = http.post(
        SERVER_URL .. "/station/update",
        json,
        headers
    )
    
    if response then
        response.close()
        return true
    else
        return false
    end
end

-- Draw a box on monitor
local function drawBox(x, y, width, height, color)
    if not useMonitor then return end
    
    monitor.setBackgroundColor(color)
    for row = y, y + height - 1 do
        monitor.setCursorPos(x, row)
        monitor.write(string.rep(" ", width))
    end
    monitor.setBackgroundColor(colors.black)
end

-- Draw text with background
local function drawText(x, y, text, textColor, bgColor)
    if not useMonitor then return end
    
    monitor.setCursorPos(x, y)
    monitor.setTextColor(textColor or colors.white)
    monitor.setBackgroundColor(bgColor or colors.black)
    monitor.write(text)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
end

-- Draw station display
local function drawStationDisplay(startX, startY, width, height, data)
    if not useMonitor then return end
    
    -- Clear area
    drawBox(startX, startY, width, height, colors.black)
    
    -- Get line color
    local lineColor = LINE_COLORS[data.line] or LINE_COLORS.default
    
    -- Header bar with line color
    drawBox(startX, startY, width, 3, lineColor)
    
    -- Station name
    local stationName = data.manifest_name or data.station_name
    if #stationName > width - 2 then
        stationName = string.sub(stationName, 1, width - 5) .. "..."
    end
    drawText(startX + 1, startY + 1, stationName, colors.white, lineColor)
    
    -- Platform and direction info
    local platformText = data.platform_name or "Platform"
    if data.direction then
        platformText = platformText .. " " .. (DIRECTION_SYMBOLS[data.direction] or data.direction)
    end
    drawText(startX + 1, startY + 2, platformText, colors.white, lineColor)
    
    -- Status area
    local statusY = startY + 4
    local statusColor = colors.lightGray
    local statusText = "IDLE"
    local trainInfo = nil
    
    if data.assembly_mode then
        statusColor = colors.purple
        statusText = "ASSEMBLY MODE"
    elseif data.train_present then
        statusColor = colors.green
        statusText = "TRAIN AT PLATFORM"
        trainInfo = data.train_name or "Unknown"
    elseif data.train_imminent then
        statusColor = colors.yellow
        statusText = "TRAIN ARRIVING"
    elseif data.train_enroute then
        statusColor = colors.orange
        statusText = "TRAIN ENROUTE"
    end
    
    -- Status box
    drawBox(startX + 1, statusY, width - 2, 3, statusColor)
    drawText(startX + 2, statusY + 1, statusText, colors.black, statusColor)
    
    if trainInfo then
        drawText(startX + 2, statusY + 2, trainInfo, colors.black, statusColor)
    end
    
    -- Next station info
    if data.next_station and manifest and manifest.stations[data.next_station] then
        local nextY = statusY + 4
        drawText(startX + 1, nextY, "Next:", colors.gray, colors.black)
        local nextName = showLatinNames and 
            manifest.stations[data.next_station].name_latin or 
            manifest.stations[data.next_station].name_en
        if #nextName > width - 7 then
            nextName = string.sub(nextName, 1, width - 10) .. "..."
        end
        drawText(startX + 7, nextY, nextName, colors.lightGray, colors.black)
    end
    
    -- Visual train indicator
    if height > 15 then
        local trackY = startY + height - 5
        
        -- Draw track
        drawBox(startX + 2, trackY, width - 4, 1, colors.gray)
        
        -- Draw direction indicator
        if data.direction then
            local dirSymbol = DIRECTION_SYMBOLS[data.direction] or "?"
            drawText(startX + width - 3, trackY, dirSymbol, colors.yellow, colors.gray)
        end
        
        -- Draw train if present
        if data.train_present then
            local trainX = startX + math.floor(width / 2) - 2
            drawBox(trainX, trackY - 1, 5, 3, colors.cyan)
            drawText(trainX + 1, trackY, "===", colors.black, colors.cyan)
        elseif data.train_imminent then
            -- Animate approaching train
            local offset = math.floor((os.clock() * 10) % 5)
            local trainX = startX + 2 + offset
            drawBox(trainX, trackY - 1, 3, 3, colors.yellow)
            drawText(trainX, trackY, ">>>", colors.black, colors.yellow)
        end
    end
    
    -- Connection info (for transfer stations)
    if data.is_transfer and data.connections and #data.connections > 0 then
        local connY = startY + height - 2
        local connections = "Transfer: " .. table.concat(data.connections, ", ")
        if #connections > width - 2 then
            connections = string.sub(connections, 1, width - 5) .. "..."
        end
        drawText(startX + 1, connY, connections, colors.lightGray, colors.black)
    end
end

-- Main display function
local function updateDisplay()
    if not useMonitor then return end
    
    monitor.clear()
    local monWidth, monHeight = monitor.getSize()
    
    -- Calculate layout
    local numStations = #STATION_IDS
    local stationsPerRow = math.min(numStations, 2)  -- Max 2 stations per row
    local rows = math.ceil(numStations / stationsPerRow)
    
    local stationWidth = math.floor(monWidth / stationsPerRow)
    local stationHeight = math.floor(monHeight / rows)
    
    -- Draw each station
    local stationIndex = 0
    for row = 1, rows do
        for col = 1, stationsPerRow do
            stationIndex = stationIndex + 1
            if stationIndex <= numStations then
                local stationId = STATION_IDS[stationIndex]
                local data = stationData[stationId]
                
                if data then
                    local x = (col - 1) * stationWidth + 1
                    local y = (row - 1) * stationHeight + 1
                    
                    drawStationDisplay(x, y, stationWidth - 1, stationHeight - 1, data)
                end
            end
        end
    end
    
    -- Footer
    drawText(1, monHeight, os.date("%H:%M:%S"), colors.gray, colors.black)
    local nameMode = showLatinNames and "Latin" or "English"
    drawText(monWidth - 15, monHeight, nameMode .. " C" .. COMPUTER_ID, colors.gray, colors.black)
end

-- Terminal display
local function displayTerminal()
    term.clear()
    term.setCursorPos(1, 1)
    
    if term.isColor() then term.setTextColor(colors.yellow) end
    print("=== MULTI-PLATFORM STATION CONTROLLER ===")
    term.setTextColor(colors.white)
    print("Computer ID: " .. COMPUTER_ID)
    print("Stations: " .. #STATION_IDS)
    print("Name Mode: " .. (showLatinNames and "Latin" or "English"))
    print("")
    
    -- Show each station status
    for i, stationId in ipairs(STATION_IDS) do
        local data = stationData[stationId]
        if data then
            if term.isColor() then 
                term.setTextColor(LINE_COLORS[data.line] or colors.white)
            end
            print("Platform " .. i .. ": " .. stationId)
            
            term.setTextColor(colors.white)
            print("  Name: " .. (data.manifest_name or data.station_name))
            print("  Line: " .. (data.line or "Unknown") .. 
                  " " .. (DIRECTION_SYMBOLS[data.direction] or ""))
            
            local status = "Idle"
            if data.train_present then
                status = "Train: " .. (data.train_name or "Unknown")
            elseif data.train_imminent then
                status = "Train arriving"
            elseif data.train_enroute then
                status = "Train enroute"
            end
            print("  Status: " .. status)
            
            if data.next_station then
                print("  Next: " .. data.next_station)
            end
            print("")
        end
    end
    
    -- Controls
    if term.isColor() then term.setTextColor(colors.gray) end
    print("Q: Quit | S: Toggle Sound | N: Toggle Names")
    print("M: Update Manifest | R: Refresh")
    term.setTextColor(colors.white)
end

-- Main program
print("Starting Multi-Platform Station Controller...")
print("Found " .. #STATION_IDS .. " stations:")
for _, id in ipairs(STATION_IDS) do
    print("  " .. id)
end

-- Play startup sound
if useSpeaker then
    playTone(262, 0.1, 0.3)  -- C4
    playTone(392, 0.1, 0.3)  -- G4
    playTone(523, 0.2, 0.3)  -- C5
end

-- Initial manifest download
print("\nDownloading station manifest...")
local err
manifest, err = downloadManifest()
if not manifest then
    print("Warning: " .. err)
    print("Continuing without manifest data...")
else
    processManifest(manifest)
    print("Manifest loaded successfully")
end

sleep(2)

-- Timers
local updateTimer = os.startTimer(0)
local lastData = {}

while true do
    local event, param = os.pullEvent()
    
    if event == "timer" and param == updateTimer then
        -- Check if manifest needs update
        if os.clock() - lastManifestUpdate > MANIFEST_UPDATE_INTERVAL then
            local newManifest, _ = downloadManifest()
            if newManifest then
                manifest = newManifest
                processManifest(manifest)
                lastManifestUpdate = os.clock()
            end
        end
        
        -- Update all stations
        for _, stationId in ipairs(STATION_IDS) do
            local station = stations[stationId]
            local data = getStationData(station, stationId)
            
            -- Send update to server
            sendUpdate(data)
            
            -- Check for changes and play sounds
            local lastStationData = lastData[stationId] or {}
            
            if not lastStationData.train_present and data.train_present then
                playStationSound("arrival", stationId)
            elseif lastStationData.train_present and not data.train_present then
                playStationSound("departure", stationId)
            elseif not lastStationData.train_imminent and data.train_imminent then
                playStationSound("imminent", stationId)
            end
            
            stationData[stationId] = data
            lastData[stationId] = data
        end
        
        -- Update displays
        displayTerminal()
        updateDisplay()
        
        updateTimer = os.startTimer(UPDATE_INTERVAL)
        
    elseif event == "key" then
        if param == keys.q then
            term.clear()
            term.setCursorPos(1, 1)
            print("Shutting down...")
            break
            
        elseif param == keys.s then
            soundEnabled = not soundEnabled
            print("Sound " .. (soundEnabled and "enabled" or "disabled"))
            sleep(1)
            
        elseif param == keys.n then
            showLatinNames = not showLatinNames
            print("Switched to " .. (showLatinNames and "Latin" or "English") .. " names")
            sleep(1)
            
        elseif param == keys.m then
            print("Updating manifest...")
            manifest, err = downloadManifest()
            if manifest then
                processManifest(manifest)
                print("Manifest updated!")
                lastManifestUpdate = os.clock()
            else
                print("Failed: " .. err)
            end
            sleep(2)
            
        elseif param == keys.r then
            print("Refreshing...")
            os.cancelTimer(updateTimer)
            updateTimer = os.startTimer(0.1)
        end
    end
end
