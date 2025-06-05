-- Train Station Network Client with Auto-Updates and Sound
-- Reports station data to central server with passenger display and audio notifications
-- Includes background update checking from GitHub

-- Configuration
local SERVER_URL = "https://ryusei.bun-procyon.ts.net"
local UPDATE_INTERVAL = 2  -- seconds for station updates
local PASSENGER_DISPLAY = true  -- Set to false for debug display

-- GitHub update configuration
local UPDATE_CHECK_INTERVAL = 3600  -- Check for updates every hour
local STARTUP_SCRIPT = "startup.lua"  -- The updater script name

-- Get computer ID for unique identification
local COMPUTER_ID = os.getComputerID()

-- Find the station peripheral (more robust detection)
local station = nil
local PERIPHERAL_NAME = nil

-- Try all possible peripheral names
local peripherals = peripheral.getNames()
for _, name in ipairs(peripherals) do
    local pType = peripheral.getType(name)
    -- Check for various possible station types
    if pType and (
        string.find(string.lower(pType), "station") or
        string.find(string.lower(pType), "create") and string.find(string.lower(pType), "station") or
        pType == "create:station" or
        pType == "createstation" or
        pType == "Create_Station"
    ) then
        -- Try to verify it's actually a station by calling a method
        local test = peripheral.wrap(name)
        if test and pcall(test.getStationName) then
            station = test
            PERIPHERAL_NAME = name
            print("Found station peripheral: " .. name .. " (type: " .. pType .. ")")
            break
        end
    end
end

if not station then
    print("ERROR: No Create train station found!")
    print("Available peripherals:")
    for _, name in ipairs(peripherals) do
        print("  " .. name .. " - " .. peripheral.getType(name))
    end
    error("Please place computer next to a Create train station")
end

-- Set unique station ID
local UNIQUE_STATION_ID = COMPUTER_ID .. ":" .. PERIPHERAL_NAME

-- Find peripherals
local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
local useMonitor = monitor ~= nil
local useSpeaker = speaker ~= nil

-- Setup monitor if available
if useMonitor then
    monitor.setTextScale(1)
    monitor.clear()
end

-- Helper functions
local function safeCall(func, ...)
    local success, result = pcall(func, ...)
    if success then
        return result
    else
        return nil
    end
end

-- Simple debug logger
local DEBUG = false  -- Set to true for debug output
local function debug(msg)
    if DEBUG then
        print("[DEBUG] " .. msg)
    end
end

-- Sound functions
local function playTone(frequency, duration, volume)
    if not useSpeaker then return end
    
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

local function playTrainSound(soundType)
    if not useSpeaker then return end
    
    if soundType == "arrival" then
        -- Two-tone arrival chime
        playTone(659, 0.3, 0.4)  -- E5
        sleep(0.1)
        playTone(523, 0.3, 0.4)  -- C5
        
    elseif soundType == "departure" then
        -- Three quick beeps
        for i = 1, 3 do
            playTone(440, 0.1, 0.3)  -- A4
            sleep(0.1)
        end
        
    elseif soundType == "imminent" then
        -- Warning tone
        playTone(392, 0.2, 0.3)  -- G4
        sleep(0.05)
        playTone(392, 0.2, 0.3)  -- G4
        
    elseif soundType == "update_check" then
        -- Quiet update check beep
        playTone(800, 0.05, 0.1)
        
    elseif soundType == "update_found" then
        -- Update notification
        playTone(523, 0.1, 0.2)  -- C5
        playTone(659, 0.1, 0.2)  -- E5
        playTone(784, 0.1, 0.2)  -- G5
    end
end

-- Helper function to write to both terminal and monitor
local function output(text, x, y, color)
    -- Terminal output
    if x and y then
        term.setCursorPos(x, y)
    end
    if color and term.isColor() then
        term.setTextColor(color)
    end
    print(text)
    term.setTextColor(colors.white)
    
    -- Monitor output (only if not in passenger mode)
    if useMonitor and not PASSENGER_DISPLAY then
        if x and y then
            monitor.setCursorPos(x, y)
        end
        if color and monitor.isColor() then
            monitor.setTextColor(color)
        end
        monitor.write(text)
        monitor.setTextColor(colors.white)
    end
end

-- Function to clear both displays
local function clearDisplays()
    term.clear()
    term.setCursorPos(1, 1)
    if useMonitor then
        monitor.clear()
        monitor.setCursorPos(1, 1)
    end
end

-- Get the actual station name (not the peripheral name)
local actualStationName = safeCall(station.getStationName) or "Unknown Station"

-- Prepare HTTP headers
local headers = {
    ["Content-Type"] = "application/json"
}

-- Train status history for passenger display
local trainHistory = {}
local maxHistory = 10

-- Sound settings
local soundEnabled = true
local lastSoundTime = 0
local SOUND_COOLDOWN = 5  -- Minimum seconds between sounds

-- Function to trigger update check
local function triggerUpdateCheck()
    -- Run the updater script in check-only mode
    playTrainSound("update_check")
    
    -- Run updater silently
    local oldTerm = term.current()
    local nullTerm = {}
    for k, v in pairs(oldTerm) do
        nullTerm[k] = function() end
    end
    term.redirect(nullTerm)
    
    local ok, result = pcall(function()
        shell.run(STARTUP_SCRIPT, "check")
    end)
    
    term.redirect(oldTerm)
    
    if ok and result then
        playTrainSound("update_found")
        return true
    end
    return false
end

-- Function to add to history
local function addToHistory(event, trainName, time)
    table.insert(trainHistory, 1, {
        event = event,
        train = trainName,
        time = time
    })
    -- Keep only recent history
    while #trainHistory > maxHistory do
        table.remove(trainHistory)
    end
end

-- Function to gather station data
local function getStationData()
    local data = {
        station_id = UNIQUE_STATION_ID,
        station_name = actualStationName,
        computer_id = COMPUTER_ID,
        peripheral_name = PERIPHERAL_NAME,
        assembly_mode = safeCall(station.isInAssemblyMode) or false,
        train_present = safeCall(station.isTrainPresent) or false,
        train_imminent = safeCall(station.isTrainImminent) or false,
        train_enroute = safeCall(station.isTrainEnroute) or false,
    }
    
    -- If train is present, get additional info
    if data.train_present then
        data.train_name = safeCall(station.getTrainName)
        data.has_schedule = safeCall(station.hasSchedule) or false
        
        if data.has_schedule then
            data.schedule = safeCall(station.getSchedule)
        end
    end
    
    return data
end

-- Function to send data to server
local function sendUpdate(data)
    local json = textutils.serialiseJSON(data)
    
    -- Debug: log what we're sending (first 200 chars)
    debug("Sending JSON: " .. string.sub(json, 1, 200) .. (string.len(json) > 200 and "..." or ""))
    
    local response = http.post(
        SERVER_URL .. "/station/update",
        json,
        headers
    )
    
    if response then
        local responseData = response.readAll()
        response.close()
        return true, responseData
    else
        -- Check if URL is allowed
        local ok, err = http.checkURL(SERVER_URL)
        if not ok then
            return false, "URL check failed: " .. (err or "unknown error")
        end
        return false, "Failed to connect to server"
    end
end

-- Function to display passenger-friendly monitor
local function displayPassengerMonitor(data)
    if not useMonitor or not PASSENGER_DISPLAY then return end
    
    monitor.clear()
    local monWidth, monHeight = monitor.getSize()
    
    -- Header with station name
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.yellow)
    local header = "=== " .. actualStationName .. " ==="
    local headerX = math.floor((monWidth - #header) / 2) + 1
    monitor.setCursorPos(headerX, 1)
    monitor.write(header)
    
    -- Current status
    monitor.setCursorPos(1, 3)
    monitor.setTextColor(colors.white)
    monitor.write("Status: ")
    
    local currentY = 3
    
    if data.train_present then
        monitor.setTextColor(colors.green)
        monitor.write("TRAIN AT PLATFORM")
        
        if data.train_name then
            monitor.setCursorPos(1, 4)
            monitor.setTextColor(colors.white)
            monitor.write("Train: ")
            monitor.setTextColor(colors.lime)
            
            -- Handle Unicode in train names
            local displayName = data.train_name
            if string.find(displayName, "?") then
                displayName = displayName .. " *"
            end
            monitor.write(displayName)
            currentY = 5
        end
    elseif data.train_imminent then
        monitor.setTextColor(colors.yellow)
        monitor.write("TRAIN ARRIVING")
        monitor.setCursorPos(1, 4)
        monitor.setTextColor(colors.gray)
        monitor.write("Please stand back")
        currentY = 5
    elseif data.train_enroute then
        monitor.setTextColor(colors.orange)
        monitor.write("TRAIN ENROUTE")
        currentY = 4
    else
        monitor.setTextColor(colors.lightGray)
        monitor.write("NO TRAINS")
        currentY = 4
    end
    
    -- Recent activity
    if #trainHistory > 0 then
        currentY = currentY + 2
        monitor.setCursorPos(1, currentY)
        monitor.setTextColor(colors.cyan)
        monitor.write("Recent Trains:")
        currentY = currentY + 1
        
        monitor.setTextColor(colors.white)
        for i, entry in ipairs(trainHistory) do
            if currentY < monHeight - 2 then
                monitor.setCursorPos(1, currentY)
                
                -- Time
                monitor.setTextColor(colors.gray)
                monitor.write(textutils.formatTime(entry.time, true) .. " ")
                
                -- Event
                if entry.event == "arrived" then
                    monitor.setTextColor(colors.green)
                    monitor.write("ARR ")
                else
                    monitor.setTextColor(colors.red)
                    monitor.write("DEP ")
                end
                
                -- Train name (truncate if needed)
                monitor.setTextColor(colors.white)
                local trainDisplay = entry.train or "Unknown"
                if #trainDisplay > monWidth - 10 then
                    trainDisplay = string.sub(trainDisplay, 1, monWidth - 13) .. "..."
                end
                monitor.write(trainDisplay)
                
                currentY = currentY + 1
            end
        end
    end
    
    -- Sound status indicator
    monitor.setCursorPos(1, monHeight - 1)
    monitor.setTextColor(colors.gray)
    monitor.write("Sound: ")
    monitor.setTextColor(soundEnabled and colors.green or colors.red)
    monitor.write(soundEnabled and "ON" or "OFF")
    
    -- Footer with time
    monitor.setCursorPos(1, monHeight)
    monitor.setTextColor(colors.gray)
    monitor.write(textutils.formatTime(os.time(), true))
    
    -- Unicode indicator
    if data.train_name and string.find(data.train_name, "?") then
        local note = "* Unicode"
        monitor.setCursorPos(monWidth - #note + 1, monHeight)
        monitor.write(note)
    end
end

-- Function to display debug monitor status
local function displayDebugMonitor(data, serverStatus, lastUpdate)
    if not useMonitor or PASSENGER_DISPLAY then return end
    
    monitor.clear()
    monitor.setCursorPos(1, 1)
    
    -- Title
    monitor.setTextColor(colors.yellow)
    monitor.write("=== TRAIN STATION DEBUG ===")
    
    -- Station info
    monitor.setCursorPos(1, 3)
    monitor.setTextColor(colors.white)
    monitor.write("Station: ")
    monitor.setTextColor(colors.cyan)
    monitor.write(data.station_name)
    
    -- Status
    monitor.setCursorPos(1, 4)
    monitor.setTextColor(colors.white)
    monitor.write("Status: ")
    
    local status = "IDLE"
    local statusColor = colors.lightGray
    
    if data.assembly_mode then
        status = "ASSEMBLY"
        statusColor = colors.purple
    elseif data.train_present then
        status = "OCCUPIED"
        statusColor = colors.green
    elseif data.train_imminent then
        status = "ARRIVING"
        statusColor = colors.yellow
    elseif data.train_enroute then
        status = "ENROUTE"
        statusColor = colors.orange
    end
    
    monitor.setTextColor(statusColor)
    monitor.write(status)
    
    -- Sound and speaker status
    monitor.setCursorPos(1, 5)
    monitor.setTextColor(colors.white)
    monitor.write("Speaker: ")
    monitor.setTextColor(useSpeaker and colors.green or colors.red)
    monitor.write(useSpeaker and "Connected" or "Not found")
    
    -- Server status
    local monWidth, monHeight = monitor.getSize()
    monitor.setCursorPos(1, monHeight - 1)
    monitor.setTextColor(colors.white)
    monitor.write("Server: ")
    
    if serverStatus == "Connected" then
        monitor.setTextColor(colors.green)
    else
        monitor.setTextColor(colors.red)
    end
    monitor.write(serverStatus)
    
    -- Debug info
    monitor.setCursorPos(1, monHeight)
    monitor.setTextColor(colors.gray)
    monitor.write("C" .. COMPUTER_ID .. ":" .. PERIPHERAL_NAME)
end

-- Function to display status in terminal
local function displayTerminalStatus(data, serverStatus, nextUpdateCheck)
    clearDisplays()
    
    output("TRAIN STATION NETWORK CLIENT", 1, 1, colors.yellow)
    output("Station: " .. data.station_name, 1, 2)
    output("Computer ID: " .. COMPUTER_ID, 1, 3, colors.lightGray)
    output("Peripheral: " .. PERIPHERAL_NAME, 1, 4, colors.lightGray)
    output("Display Mode: " .. (PASSENGER_DISPLAY and "Passenger" or "Debug"), 1, 5, colors.cyan)
    output("Speaker: " .. (useSpeaker and "Connected" or "Not found"), 1, 6, useSpeaker and colors.green or colors.red)
    output("Sound: " .. (soundEnabled and "Enabled" or "Disabled"), 1, 7, soundEnabled and colors.green or colors.red)
    
    -- Next update check info
    if nextUpdateCheck then
        local timeUntil = math.floor(nextUpdateCheck - os.clock())
        output("Next update check in: " .. timeUntil .. "s", 1, 8, colors.gray)
    end
    
    output(string.rep("-", 40), 1, 9)
    
    -- Status
    local status = "IDLE"
    if data.assembly_mode then
        status = "ASSEMBLY MODE"
    elseif data.train_present then
        status = "TRAIN PRESENT: " .. (data.train_name or "Unknown")
    elseif data.train_imminent then
        status = "TRAIN ARRIVING"
    elseif data.train_enroute then
        status = "TRAIN ENROUTE"
    end
    
    output("Status: " .. status, 1, 11, colors.green)
    
    -- Server connection
    output("Server: " .. serverStatus, 1, 13, serverStatus == "Connected" and colors.green or colors.red)
    
    -- Instructions
    output("", 1, 15)
    output("Controls:", 1, 15, colors.yellow)
    output("Q: Quit | M: Toggle monitor | S: Network status", 1, 16, colors.gray)
    output("U: Update now | R: Restart | T: Toggle sound", 1, 17, colors.gray)
end

-- Function to get network status from server
local function getNetworkStatus()
    local response = http.get(SERVER_URL .. "/network/status")
    
    if response then
        local data = textutils.unserialiseJSON(response.readAll())
        response.close()
        
        clearDisplays()
        output("NETWORK STATUS", 1, 1, colors.yellow)
        output(string.rep("-", 40), 1, 2)
        output("Active Stations: " .. data.active_stations .. "/" .. data.total_stations, 1, 3)
        output("Total Trains: " .. data.total_trains, 1, 4)
        output("Trains in Motion: " .. data.trains_in_motion, 1, 5)
        output("Occupied Stations: " .. data.occupied_stations, 1, 6)
        output("Recent Movements: " .. data.recent_movements, 1, 7)
        output("", 1, 9)
        output("Press any key to continue...", 1, 9, colors.gray)
        os.pullEvent("key")
    else
        output("Failed to get network status", 1, 1, colors.red)
        sleep(2)
    end
end

-- Main loop
output("Starting Train Station Network Client...", 1, 1, colors.yellow)
output("Computer ID: " .. COMPUTER_ID, 1, 2, colors.lightGray)
output("Station: " .. actualStationName, 1, 3, colors.cyan)
output("Peripheral: " .. PERIPHERAL_NAME .. " (" .. peripheral.getType(PERIPHERAL_NAME) .. ")", 1, 4)
output("Monitor: " .. (useMonitor and "Connected" or "Not found"), 1, 5, useMonitor and colors.green or colors.red)
output("Speaker: " .. (useSpeaker and "Connected" or "Not found"), 1, 6, useSpeaker and colors.green or colors.red)
output("Display Mode: " .. (PASSENGER_DISPLAY and "Passenger" or "Debug"), 1, 7, colors.cyan)
output("GitHub Updates: Enabled", 1, 8, colors.green)

-- Play startup sound
if useSpeaker then
    playTone(262, 0.1, 0.2)  -- C4
    sleep(0.05)
    playTone(392, 0.2, 0.2)  -- G4
end

sleep(3)

local lastData = {}
local updateTimer = os.startTimer(0)
local lastUpdateTime = os.time()
local lastUpdateCheck = os.clock()
local nextUpdateCheck = os.clock() + UPDATE_CHECK_INTERVAL

while true do
    local event, param = os.pullEvent()
    
    if event == "timer" and param == updateTimer then
        -- Gather and send data
        local data = getStationData()
        local success, response = sendUpdate(data)
        
        local serverStatus = success and "Connected" or "Error"
        if not success then
            -- Show more detailed error
            print("Server error: " .. response)
        end
        
        -- Check for significant changes for passenger display and sounds
        if PASSENGER_DISPLAY then
            local currentTime = os.clock()
            
            -- Train arrival
            if not lastData.train_present and data.train_present then
                addToHistory("arrived", data.train_name or "Unknown", os.time())
                if soundEnabled and (currentTime - lastSoundTime > SOUND_COOLDOWN) then
                    playTrainSound("arrival")
                    lastSoundTime = currentTime
                end
                
            -- Train departure
            elseif lastData.train_present and not data.train_present then
                if lastData.train_name then
                    addToHistory("departed", lastData.train_name, os.time())
                end
                if soundEnabled and (currentTime - lastSoundTime > SOUND_COOLDOWN) then
                    playTrainSound("departure")
                    lastSoundTime = currentTime
                end
                
            -- Train imminent
            elseif not lastData.train_imminent and data.train_imminent then
                if soundEnabled and (currentTime - lastSoundTime > SOUND_COOLDOWN) then
                    playTrainSound("imminent")
                    lastSoundTime = currentTime
                end
            end
        end
        
        -- Check for updates periodically
        if os.clock() >= nextUpdateCheck then
            local hasUpdate = triggerUpdateCheck()
            nextUpdateCheck = os.clock() + UPDATE_CHECK_INTERVAL
            
            if hasUpdate then
                -- Schedule restart in 30 seconds
                output("Update available! Restarting in 30 seconds...", 1, 1, colors.yellow)
                os.startTimer(30)
            end
        end
        
        -- Display status
        displayTerminalStatus(data, serverStatus, nextUpdateCheck)
        
        if PASSENGER_DISPLAY then
            displayPassengerMonitor(data)
        else
            displayDebugMonitor(data, serverStatus, lastUpdateTime)
        end
        
        lastData = data
        lastUpdateTime = os.time()
        updateTimer = os.startTimer(UPDATE_INTERVAL)
        
    elseif event == "key" then
        if param == keys.q then
            clearDisplays()
            output("Client stopped.", 1, 1)
            break
            
        elseif param == keys.m then
            -- Toggle monitor mode
            PASSENGER_DISPLAY = not PASSENGER_DISPLAY
            output("Switched to " .. (PASSENGER_DISPLAY and "Passenger" or "Debug") .. " display", 1, 1, colors.yellow)
            sleep(1)
            
        elseif param == keys.s then
            getNetworkStatus()
            
        elseif param == keys.t then
            -- Toggle sound
            soundEnabled = not soundEnabled
            output("Sound " .. (soundEnabled and "enabled" or "disabled"), 1, 1, colors.yellow)
            if soundEnabled and useSpeaker then
                playTone(440, 0.1, 0.2)  -- Test beep
            end
            sleep(1)
            
        elseif param == keys.u then
            -- Manual update check
            output("Checking for GitHub updates...", 1, 1, colors.yellow)
            local hasUpdate = triggerUpdateCheck()
            if hasUpdate then
                output("Update found! Restarting in 5 seconds...", 1, 2, colors.green)
                sleep(5)
                os.reboot()
            else
                output("No updates available", 1, 2, colors.gray)
                sleep(2)
            end
            
        elseif param == keys.r then
            -- Manual restart
            clearDisplays()
            output("Restarting...", 1, 1, colors.orange)
            sleep(1)
            os.reboot()
        end
    end
end
