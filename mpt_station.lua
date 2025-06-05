-- Multi-Platform Train Station Controller with Graphics
-- Supports multiple station peripherals on one computer with visual display

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
local STATION_PERIPHERALS = {}

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
            stations[name] = test
            table.insert(STATION_PERIPHERALS, name)
            print("Found station: " .. name .. " (" .. pType .. ")")
        end
    end
end

if #STATION_PERIPHERALS == 0 then
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
local stationData = {}  -- Keyed by peripheral name
local lastManifestUpdate = 0
local soundEnabled = true
local lastSoundTime = {}  -- Per station

-- Colors for lines (ComputerCraft colors)
local LINE_COLORS = {
    K = colors.brown,
    P = colors.orange,
    CM = colors.red,
    default = colors.gray
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

local function playStationSound(soundType, stationName)
    if not useSpeaker or not soundEnabled then return end
    
    -- Check cooldown per station
    local currentTime = os.clock()
    if lastSoundTime[stationName] and (currentTime - lastSoundTime[stationName] < 10) then
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
    
    lastSoundTime[stationName] = currentTime
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

-- Find station info in manifest
local function findStationInManifest(computerID, peripheralName)
    if not manifest then return nil end
    
    for lineId, line in pairs(manifest.lines) do
        for _, station in ipairs(line.stations) do
            -- Check simple station
            if type(station.computer_id) == "number" then
                if station.computer_id == computerID and station.peripheral == peripheralName then
                    return {
                        station = station,
                        line = lineId,
                        line_info = line
                    }
                end
            -- Check multi-computer station
            elseif type(station.computer_id) == "table" then
                for _, cid in ipairs(station.computer_id) do
                    if cid == computerID and station.peripheral == peripheralName then
                        return {
                            station = station,
                            line = lineId,
                            line_info = line
                        }
                    end
                end
            end
            
            -- Check platforms
            if station.platforms then
                for platformName, platform in pairs(station.platforms) do
                    if platform.computer_id == computerID and platform.peripheral == peripheralName then
                        return {
                            station = station,
                            line = lineId,
                            line_info = line,
                            platform = platformName
                        }
                    end
                end
            end
        end
    end
    
    return nil
end

-- Gather data from a station peripheral
local function getStationData(station, peripheralName)
    local data = {
        station_id = COMPUTER_ID .. ":" .. peripheralName,
        computer_id = COMPUTER_ID,
        peripheral_name = peripheralName,
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
    
    -- Add manifest info
    local manifestInfo = findStationInManifest(COMPUTER_ID, peripheralName)
    if manifestInfo then
        data.line = manifestInfo.line
        data.line_info = manifestInfo.line_info
        data.manifest_station = manifestInfo.station
        data.platform = manifestInfo.platform
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
    local stationName = data.manifest_station and data.manifest_station.name or data.station_name
    local displayName = stationName
    if #displayName > width - 2 then
        displayName = string.sub(displayName, 1, width - 5) .. "..."
    end
    
    drawText(startX + 1, startY + 1, displayName, colors.white, lineColor)
    
    -- Line and platform info
    local lineInfo = data.line or "?"
    if data.platform then
        lineInfo = lineInfo .. " (" .. data.platform .. ")"
    end
    drawText(startX + 1, startY + 2, lineInfo, colors.white, lineColor)
    
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
    
    -- Visual train indicator
    if height > 12 then
        local trackY = startY + 9
        
        -- Draw track
        drawBox(startX + 2, trackY, width - 4, 1, colors.gray)
        
        -- Draw train if present
        if data.train_present then
            local trainX = startX + math.floor(width / 2) - 2
            drawBox(trainX, trackY - 1, 5, 3, colors.cyan)
            drawText(trainX + 1, trackY, "███", colors.black, colors.cyan)
        elseif data.train_imminent then
            -- Animate approaching train
            local offset = math.floor((os.clock() * 10) % 5)
            local trainX = startX + 2 + offset
            drawBox(trainX, trackY - 1, 3, 3, colors.yellow)
            drawText(trainX, trackY, ">>>", colors.black, colors.yellow)
        end
    end
    
    -- Connection info
    if data.manifest_station and data.manifest_station.connections and #data.manifest_station.connections > 0 then
        local connY = startY + height - 2
        local connections = "↔ " .. table.concat(data.manifest_station.connections, ", ")
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
    local numStations = #STATION_PERIPHERALS
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
                local peripheralName = STATION_PERIPHERALS[stationIndex]
                local data = stationData[peripheralName]
                
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
    drawText(monWidth - 10, monHeight, "C" .. COMPUTER_ID, colors.gray, colors.black)
end

-- Terminal display
local function displayTerminal()
    term.clear()
    term.setCursorPos(1, 1)
    
    if term.isColor() then term.setTextColor(colors.yellow) end
    print("=== MULTI-PLATFORM STATION CONTROLLER ===")
    term.setTextColor(colors.white)
    print("Computer ID: " .. COMPUTER_ID)
    print("Stations: " .. #STATION_PERIPHERALS)
    print("")
    
    -- Show each station status
    for i, peripheralName in ipairs(STATION_PERIPHERALS) do
        local data = stationData[peripheralName]
        if data then
            if term.isColor() then 
                term.setTextColor(LINE_COLORS[data.line] or colors.white)
            end
            print("Station " .. i .. ": " .. peripheralName)
            
            term.setTextColor(colors.white)
            print("  Name: " .. (data.manifest_station and data.manifest_station.name or data.station_name))
            print("  Line: " .. (data.line or "Unknown"))
            
            local status = "Idle"
            if data.train_present then
                status = "Train: " .. (data.train_name or "Unknown")
            elseif data.train_imminent then
                status = "Train arriving"
            elseif data.train_enroute then
                status = "Train enroute"
            end
            print("  Status: " .. status)
            print("")
        end
    end
    
    -- Controls
    if term.isColor() then term.setTextColor(colors.gray) end
    print("Q: Quit | S: Toggle Sound | M: Update Manifest")
    term.setTextColor(colors.white)
end

-- Main loop
print("Starting Multi-Platform Station Controller...")
print("Found " .. #STATION_PERIPHERALS .. " stations")

-- Play startup sound
if useSpeaker then
    playTone(262, 0.1, 0.3)  -- C4
    playTone(392, 0.1, 0.3)  -- G4
    playTone(523, 0.2, 0.3)  -- C5
end

-- Initial manifest download
print("Downloading station manifest...")
local err
manifest, err = downloadManifest()
if not manifest then
    print("Warning: " .. err)
    print("Continuing without manifest data...")
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
                lastManifestUpdate = os.clock()
            end
        end
        
        -- Update all stations
        for _, peripheralName in ipairs(STATION_PERIPHERALS) do
            local station = stations[peripheralName]
            local data = getStationData(station, peripheralName)
            
            -- Send update to server
            sendUpdate(data)
            
            -- Check for changes and play sounds
            local lastStationData = lastData[peripheralName] or {}
            
            if not lastStationData.train_present and data.train_present then
                playStationSound("arrival", peripheralName)
            elseif lastStationData.train_present and not data.train_present then
                playStationSound("departure", peripheralName)
            elseif not lastStationData.train_imminent and data.train_imminent then
                playStationSound("imminent", peripheralName)
            end
            
            stationData[peripheralName] = data
            lastData[peripheralName] = data
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
            
        elseif param == keys.m then
            print("Updating manifest...")
            manifest, err = downloadManifest()
            if manifest then
                print("Manifest updated!")
                lastManifestUpdate = os.clock()
            else
                print("Failed: " .. err)
            end
            sleep(2)
        end
    end
end
