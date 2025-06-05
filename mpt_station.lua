-- Multi-Platform Train Station Controller with Multiple Monitor Support
-- Supports three monitor configurations per computer:
--   1. Central monitor only - Overview of all platforms
--   2. Platform monitors only - Dedicated display per platform
--   3. Both central and platform monitors
-- Configuration is per-computer ID in the manifest
-- Layout dynamically adjusts based on number of platforms
-- Version 3.0 - Uses manifest-based monitor configuration

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

-- Find all monitors
local monitors = {}
local centralMonitor = nil

-- Scan for all monitors
for _, name in ipairs(peripherals) do
    if peripheral.getType(name) == "monitor" then
        local mon = peripheral.wrap(name)
        if mon then
            monitors[name] = mon
            print("Found monitor: " .. name)
        end
    end
end

-- Find speaker
local speaker = peripheral.find("speaker")
local useSpeaker = speaker ~= nil

-- Global state
local manifest = nil
local stationData = {}  -- Keyed by station ID
local platformInfo = {}  -- Manifest data per station ID
local platformMonitors = {}  -- Maps station ID to dedicated monitor
local computerConfig = nil  -- This computer's configuration
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

-- Process manifest to create platform lookup and configure monitors
local function processManifest(manifest)
    platformInfo = {}
    platformMonitors = {}
    
    -- Get computer-specific configuration
    computerConfig = nil
    if manifest.computer_configs then
        -- Try to find config for this computer ID
        computerConfig = manifest.computer_configs[tostring(COMPUTER_ID)]
        
        -- Fall back to default if not found
        if not computerConfig and manifest.computer_configs.default then
            computerConfig = manifest.computer_configs.default
            print("Using default computer configuration")
        end
    end
    
    -- Configure central monitor if specified in computer config
    if computerConfig and computerConfig.central_monitor then
        centralMonitor = monitors[computerConfig.central_monitor]
        if centralMonitor then
            centralMonitor.setTextScale(0.5)
            centralMonitor.clear()
            print("Central monitor configured: " .. computerConfig.central_monitor)
        else
            print("Warning: Central monitor '" .. computerConfig.central_monitor .. "' not found")
            centralMonitor = nil
        end
    else
        -- No central monitor specified for this computer
        centralMonitor = nil
        print("No central monitor configured for computer " .. COMPUTER_ID)
    end
    
    -- Process platforms
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
                display_order = platform.display_order or 999,
                connections = {}
            }
            
            -- Build connections list
            for _, line in ipairs(station.lines) do
                if line ~= platform.line then
                    table.insert(platformInfo[platformId].connections, line)
                end
            end
            
            -- Configure platform-specific monitor if specified
            if platform.monitor and monitors[platform.monitor] then
                platformMonitors[platformId] = monitors[platform.monitor]
                platformMonitors[platformId].setTextScale(1)
                platformMonitors[platformId].clear()
                print("Platform monitor for " .. platformId .. ": " .. platform.monitor)
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
        data.display_order = pInfo.display_order
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
local function drawBox(monitor, x, y, width, height, color)
    if not monitor then return end
    
    monitor.setBackgroundColor(color)
    for row = y, y + height - 1 do
        monitor.setCursorPos(x, row)
        monitor.write(string.rep(" ", width))
    end
    monitor.setBackgroundColor(colors.black)
end

-- Draw text with background
local function drawText(monitor, x, y, text, textColor, bgColor)
    if not monitor then return end
    
    monitor.setCursorPos(x, y)
    monitor.setTextColor(textColor or colors.white)
    monitor.setBackgroundColor(bgColor or colors.black)
    monitor.write(text)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
end

-- Draw station display on a monitor
local function drawStationDisplay(monitor, startX, startY, width, height, data)
    if not monitor then return end
    
    -- Clear area
    drawBox(monitor, startX, startY, width, height, colors.black)
    
    -- Get line color
    local lineColor = LINE_COLORS[data.line] or LINE_COLORS.default
    
    -- Minimum display mode for very small areas
    if height < 8 or width < 15 then
        -- Ultra compact mode - just show line and status
        drawBox(monitor, startX, startY, width, 1, lineColor)
        local shortName = string.sub(data.platform_name or data.station_name, 1, width - 2)
        drawText(monitor, startX + 1, startY, shortName, colors.white, lineColor)
        
        local statusY = startY + 2
        local statusChar = " "
        local statusColor = colors.lightGray
        
        if data.train_present then
            statusChar = "T"
            statusColor = colors.green
        elseif data.train_imminent then
            statusChar = "!"
            statusColor = colors.yellow
        elseif data.train_enroute then
            statusChar = "~"
            statusColor = colors.orange
        end
        
        drawText(monitor, startX + math.floor(width/2), statusY, statusChar, statusColor, colors.black)
        return
    end
    
    -- Normal display mode
    -- Header bar with line color
    local headerHeight = math.min(3, math.floor(height * 0.3))
    drawBox(monitor, startX, startY, width, headerHeight, lineColor)
    
    -- Station name
    local stationName = data.manifest_name or data.station_name
    if #stationName > width - 2 then
        stationName = string.sub(stationName, 1, width - 5) .. "..."
    end
    drawText(monitor, startX + 1, startY + 1, stationName, colors.white, lineColor)
    
    -- Platform and direction info (if space allows)
    if headerHeight >= 2 then
        local platformText = data.platform_name or "Platform"
        if data.direction then
            platformText = platformText .. " " .. (DIRECTION_SYMBOLS[data.direction] or data.direction)
        end
        if #platformText > width - 2 then
            platformText = string.sub(platformText, 1, width - 5) .. "..."
        end
        drawText(monitor, startX + 1, startY + 2, platformText, colors.white, lineColor)
    end
    
    -- Status area
    local statusY = startY + headerHeight + 1
    local statusHeight = math.min(3, math.floor(height * 0.3))
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
    if height > 10 then
        drawBox(monitor, startX + 1, statusY, width - 2, statusHeight, statusColor)
        
        -- Center status text
        if #statusText > width - 4 then
            statusText = string.sub(statusText, 1, width - 7) .. "..."
        end
        local statusX = startX + math.floor((width - #statusText) / 2)
        drawText(monitor, statusX, statusY + 1, statusText, colors.black, statusColor)
        
        if trainInfo and statusHeight > 2 then
            if #trainInfo > width - 4 then
                trainInfo = string.sub(trainInfo, 1, width - 7) .. "..."
            end
            local trainX = startX + math.floor((width - #trainInfo) / 2)
            drawText(monitor, trainX, statusY + 2, trainInfo, colors.black, statusColor)
        end
    else
        -- Compact status display
        if #statusText > width - 2 then
            statusText = string.sub(statusText, 1, 3) .. ".."
        end
        drawText(monitor, startX + 1, statusY, statusText, statusColor, colors.black)
    end
    
    -- Next station info (if space allows)
    if height > 12 and data.next_station and manifest and manifest.stations[data.next_station] then
        local nextY = statusY + statusHeight + 1
        drawText(monitor, startX + 1, nextY, "Next:", colors.gray, colors.black)
        local nextName = showLatinNames and 
            manifest.stations[data.next_station].name_latin or 
            manifest.stations[data.next_station].name_en
        if #nextName > width - 7 then
            nextName = string.sub(nextName, 1, width - 10) .. "..."
        end
        drawText(monitor, startX + 7, nextY, nextName, colors.lightGray, colors.black)
    end
    
    -- Visual train indicator (only if enough space)
    if height > 15 then
        local trackY = startY + height - 5
        
        -- Draw track
        drawBox(monitor, startX + 2, trackY, width - 4, 1, colors.gray)
        
        -- Draw direction indicator
        if data.direction then
            local dirSymbol = DIRECTION_SYMBOLS[data.direction] or "?"
            drawText(monitor, startX + width - 3, trackY, dirSymbol, colors.yellow, colors.gray)
        end
        
        -- Draw train if present
        if data.train_present then
            local trainX = startX + math.floor(width / 2) - 2
            drawBox(monitor, trainX, trackY - 1, 5, 3, colors.cyan)
            drawText(monitor, trainX + 1, trackY, "===", colors.black, colors.cyan)
        elseif data.train_imminent then
            -- Animate approaching train
            local offset = math.floor((os.clock() * 10) % 5)
            local trainX = startX + 2 + offset
            if trainX + 3 < startX + width - 2 then
                drawBox(monitor, trainX, trackY - 1, 3, 3, colors.yellow)
                drawText(monitor, trainX, trackY, ">>>", colors.black, colors.yellow)
            end
        end
    end
    
    -- Connection info (for transfer stations, only if space)
    if height > 18 and data.is_transfer and data.connections and #data.connections > 0 then
        local connY = startY + height - 2
        local connections = "Transfer: " .. table.concat(data.connections, ", ")
        if #connections > width - 2 then
            connections = string.sub(connections, 1, width - 5) .. "..."
        end
        drawText(monitor, startX + 1, connY, connections, colors.lightGray, colors.black)
    end
end

-- Draw individual platform monitor (full screen)
local function drawPlatformMonitor(monitor, data)
    if not monitor then return end
    
    monitor.clear()
    local monWidth, monHeight = monitor.getSize()
    
    -- Get line color
    local lineColor = LINE_COLORS[data.line] or LINE_COLORS.default
    
    -- Large header
    drawBox(monitor, 1, 1, monWidth, 4, lineColor)
    
    -- Station name (centered)
    local stationName = data.manifest_name or data.station_name
    local nameX = math.floor((monWidth - #stationName) / 2) + 1
    drawText(monitor, nameX, 2, stationName, colors.white, lineColor)
    
    -- Platform info (centered)
    local platformText = data.platform_name or "Platform"
    if data.direction then
        platformText = platformText .. " " .. (DIRECTION_SYMBOLS[data.direction] or data.direction)
    end
    local platX = math.floor((monWidth - #platformText) / 2) + 1
    drawText(monitor, platX, 3, platformText, colors.white, lineColor)
    
    -- Large status display
    local statusY = 6
    local statusHeight = 5
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
    drawBox(monitor, 2, statusY, monWidth - 2, statusHeight, statusColor)
    local statusX = math.floor((monWidth - #statusText) / 2) + 1
    drawText(monitor, statusX, statusY + 2, statusText, colors.black, statusColor)
    
    if trainInfo then
        local trainX = math.floor((monWidth - #trainInfo) / 2) + 1
        drawText(monitor, trainX, statusY + 3, trainInfo, colors.black, statusColor)
    end
    
    -- Next station
    if data.next_station and manifest and manifest.stations[data.next_station] then
        local nextY = statusY + statusHeight + 2
        local nextName = showLatinNames and 
            manifest.stations[data.next_station].name_latin or 
            manifest.stations[data.next_station].name_en
        local nextText = "Next: " .. nextName
        local nextX = math.floor((monWidth - #nextText) / 2) + 1
        drawText(monitor, nextX, nextY, nextText, colors.lightGray, colors.black)
    end
    
    -- Large visual indicator
    local visualY = monHeight - 8
    
    -- Draw platform
    drawBox(monitor, 2, visualY + 3, monWidth - 2, 2, colors.gray)
    
    -- Draw train visualization
    if data.train_present then
        -- Large train
        local trainWidth = math.min(monWidth - 4, 20)
        local trainX = math.floor((monWidth - trainWidth) / 2) + 1
        drawBox(monitor, trainX, visualY, trainWidth, 5, colors.cyan)
        
        -- Train details
        local trainText = "[===TRAIN===]"
        local textX = math.floor((monWidth - #trainText) / 2) + 1
        drawText(monitor, textX, visualY + 2, trainText, colors.black, colors.cyan)
        
    elseif data.train_imminent then
        -- Animated approaching indicator
        local phase = math.floor((os.clock() * 2) % 3)
        local arrow = phase == 0 and ">>>" or phase == 1 and " >>>" or "  >>>"
        drawText(monitor, 4, visualY + 2, arrow, colors.yellow, colors.black)
        drawText(monitor, 6 + #arrow, visualY + 2, "APPROACHING", colors.yellow, colors.black)
    end
    
    -- Time and line indicator
    drawText(monitor, 1, monHeight, os.date("%H:%M:%S"), colors.gray, colors.black)
    drawText(monitor, monWidth - 10, monHeight, "Line " .. data.line, lineColor, colors.black)
end

-- Update central display
local function updateCentralDisplay()
    if not centralMonitor then return end
    
    centralMonitor.clear()
    local monWidth, monHeight = centralMonitor.getSize()
    
    -- Sort stations by display_order
    local sortedStations = {}
    for stationId, data in pairs(stationData) do
        table.insert(sortedStations, {id = stationId, data = data})
    end
    table.sort(sortedStations, function(a, b)
        local orderA = a.data.display_order or 999
        local orderB = b.data.display_order or 999
        return orderA < orderB
    end)
    
    -- Calculate dynamic layout
    local numStations = #sortedStations
    if numStations == 0 then return end
    
    -- Get configured columns or calculate based on monitor width
    local layoutCols = 2  -- Default
    if computerConfig and computerConfig.layout_columns then
        if type(computerConfig.layout_columns) == "number" and computerConfig.layout_columns > 0 then
            layoutCols = computerConfig.layout_columns
        elseif computerConfig.layout_columns == "auto" then
            -- Auto-calculate columns based on monitor width
            -- Assume each station needs at least 25 chars width
            layoutCols = math.max(1, math.floor(monWidth / 25))
        end
    else
        -- Auto-calculate columns based on monitor width
        layoutCols = math.max(1, math.floor(monWidth / 25))
    end
    
    -- Calculate rows needed
    local layoutRows = math.ceil(numStations / layoutCols)
    
    -- Calculate display dimensions
    local stationWidth = math.floor(monWidth / layoutCols)
    local stationHeight = math.floor((monHeight - 1) / layoutRows)  -- -1 for footer
    
    -- Ensure minimum height
    if stationHeight < 10 then
        -- Too many stations for display, try to adjust
        if layoutCols > 1 then
            layoutCols = math.max(1, layoutCols - 1)
            layoutRows = math.ceil(numStations / layoutCols)
            stationWidth = math.floor(monWidth / layoutCols)
            stationHeight = math.floor((monHeight - 1) / layoutRows)
        end
        
        -- If still too small, use ultra-compact mode
        if stationHeight < 6 then
            print("Warning: Monitor too small for " .. numStations .. " stations")
        end
    end
    
    -- Draw each station in order
    for index, station in ipairs(sortedStations) do
        if index <= layoutCols * layoutRows then
            local col = ((index - 1) % layoutCols) + 1
            local row = math.floor((index - 1) / layoutCols) + 1
            
            local x = (col - 1) * stationWidth + 1
            local y = (row - 1) * stationHeight + 1
            
            -- Ensure we don't overflow the monitor
            if y + stationHeight <= monHeight then
                drawStationDisplay(centralMonitor, x, y, stationWidth - 1, stationHeight - 1, station.data)
            end
        end
    end
    
    -- Footer
    drawText(centralMonitor, 1, monHeight, os.date("%H:%M:%S"), colors.gray, colors.black)
    local nameMode = showLatinNames and "Latin" or "English"
    local layoutInfo = layoutCols .. "x" .. layoutRows
    if computerConfig and computerConfig.layout_columns == "auto" then
        layoutInfo = layoutInfo .. "A"  -- A for auto
    end
    drawText(centralMonitor, monWidth - 22, monHeight, layoutInfo .. " " .. nameMode .. " C" .. COMPUTER_ID, colors.gray, colors.black)
end

-- Update individual platform monitors
local function updatePlatformMonitors()
    for stationId, monitor in pairs(platformMonitors) do
        local data = stationData[stationId]
        if data then
            drawPlatformMonitor(monitor, data)
        end
    end
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
    
    -- Show monitor configuration
    local monitorConfig = "Monitors: "
    local monitorCount = 0
    if centralMonitor then
        monitorConfig = monitorConfig .. "Central"
        monitorCount = monitorCount + 1
    end
    
    local platformMonCount = 0
    for _ in pairs(platformMonitors) do
        platformMonCount = platformMonCount + 1
    end
    
    if platformMonCount > 0 then
        if monitorCount > 0 then
            monitorConfig = monitorConfig .. " + "
        end
        monitorConfig = monitorConfig .. platformMonCount .. " platform"
        monitorCount = monitorCount + platformMonCount
    end
    
    if monitorCount == 0 then
        monitorConfig = monitorConfig .. "None (terminal only)"
    end
    
    print(monitorConfig)
    print("Name Mode: " .. (showLatinNames and "Latin" or "English"))
    print("")
    
    -- Sort stations for terminal display
    local sortedStations = {}
    for stationId, data in pairs(stationData) do
        table.insert(sortedStations, {id = stationId, data = data})
    end
    table.sort(sortedStations, function(a, b)
        local orderA = a.data.display_order or 999
        local orderB = b.data.display_order or 999
        return orderA < orderB
    end)
    
    -- Show each station status
    for index, station in ipairs(sortedStations) do
        local data = station.data
        
        if term.isColor() then 
            term.setTextColor(LINE_COLORS[data.line] or colors.white)
        end
        print("Platform " .. index .. ": " .. station.id)
        
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
        
        -- Show if has dedicated monitor
        if platformMonitors[station.id] then
            if term.isColor() then term.setTextColor(colors.lightBlue) end
            print("  [Has dedicated monitor]")
            term.setTextColor(colors.white)
        end
        
        print("")
    end
    
    -- Controls
    if term.isColor() then term.setTextColor(colors.gray) end
    print("Q: Quit | S: Toggle Sound | N: Toggle Names")
    print("M: Update Manifest | R: Refresh")
    term.setTextColor(colors.white)
end

-- Main program
print("Starting Multi-Platform Station Controller...")
print("Found " .. #STATION_IDS .. " stations")

-- Count monitors
local monitorCount = 0
for _ in pairs(monitors) do
    monitorCount = monitorCount + 1
end
print("Found " .. monitorCount .. " monitors")

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
    
    -- Report monitor configuration
    print("\nMonitor configuration:")
    if computerConfig then
        print("  Using config for computer " .. COMPUTER_ID)
    else
        print("  No config found for computer " .. COMPUTER_ID)
        if manifest and manifest.computer_configs and manifest.computer_configs.default then
            print("  (Default config exists but wasn't applied)")
        end
    end
    
    if centralMonitor then
        print("  Central monitor: Active")
        if computerConfig and computerConfig.layout_columns then
            if computerConfig.layout_columns == "auto" then
                print("  Layout columns: Auto")
            else
                print("  Layout columns: " .. computerConfig.layout_columns)
            end
        else
            print("  Layout columns: Auto")
        end
    else
        print("  Central monitor: Not configured")
    end
    
    local platformMonCount = 0
    for _ in pairs(platformMonitors) do
        platformMonCount = platformMonCount + 1
    end
    
    if platformMonCount > 0 then
        print("  Platform monitors: " .. platformMonCount .. " active")
        for stationId, _ in pairs(platformMonitors) do
            local pInfo = platformInfo[stationId]
            if pInfo then
                print("    - " .. (pInfo.platform_name or stationId))
            end
        end
    else
        print("  Platform monitors: None configured")
    end
    
    if not centralMonitor and platformMonCount == 0 then
        print("  Running in terminal-only mode")
    end
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
        updateCentralDisplay()
        updatePlatformMonitors()
        
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
