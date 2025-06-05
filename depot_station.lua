-- Minimal Depot Station Client for Create Mod
-- Provides assembly/disassembly controls and web reporting
-- No monitor support - terminal only operation

-- Configuration
local SERVER_URL = "https://ryusei.bun-procyon.ts.net"
local UPDATE_INTERVAL = 5  -- seconds between status updates
local DEPOT_MODE = true  -- Identifies this as a depot station

-- Get computer ID for unique identification
local COMPUTER_ID = os.getComputerID()

-- Find the station peripheral
local station = nil
local PERIPHERAL_NAME = nil

-- Try all possible peripheral names
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
            station = test
            PERIPHERAL_NAME = name
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
    error("Please place computer next to a Create depot station")
end

-- Set unique station ID
local UNIQUE_STATION_ID = COMPUTER_ID .. ":" .. PERIPHERAL_NAME

-- Find speaker for audio feedback
local speaker = peripheral.find("speaker")
local useSpeaker = speaker ~= nil

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

local function playSound(soundType)
    if not useSpeaker then return end
    
    if soundType == "assemble_start" then
        -- Rising tones for assembly
        playTone(440, 0.1, 0.3)  -- A4
        playTone(523, 0.1, 0.3)  -- C5
        playTone(659, 0.2, 0.3)  -- E5
        
    elseif soundType == "assemble_complete" then
        -- Success fanfare
        playTone(523, 0.1, 0.3)  -- C5
        playTone(659, 0.1, 0.3)  -- E5
        playTone(784, 0.1, 0.3)  -- G5
        playTone(1047, 0.3, 0.4) -- C6
        
    elseif soundType == "disassemble" then
        -- Descending tones
        playTone(659, 0.1, 0.3)  -- E5
        playTone(523, 0.1, 0.3)  -- C5
        playTone(440, 0.1, 0.3)  -- A4
        playTone(349, 0.2, 0.3)  -- F4
        
    elseif soundType == "error" then
        -- Error beep
        playTone(220, 0.3, 0.4)  -- A3
        sleep(0.1)
        playTone(220, 0.3, 0.4)  -- A3
        
    elseif soundType == "beep" then
        -- Simple beep
        playTone(600, 0.05, 0.2)
    end
end

-- Get the actual station name
local actualStationName = safeCall(station.getStationName) or "Unknown Depot"

-- HTTP headers
local headers = {
    ["Content-Type"] = "application/json"
}

-- Function to gather station data
local function getStationData()
    local data = {
        station_id = UNIQUE_STATION_ID,
        station_name = actualStationName,
        computer_id = COMPUTER_ID,
        peripheral_name = PERIPHERAL_NAME,
        depot_mode = DEPOT_MODE,
        assembly_mode = safeCall(station.isInAssemblyMode) or false,
        train_present = safeCall(station.isTrainPresent) or false,
        train_imminent = safeCall(station.isTrainImminent) or false,
        train_enroute = safeCall(station.isTrainEnroute) or false,
    }
    
    -- If train is present, get additional info
    if data.train_present then
        data.train_name = safeCall(station.getTrainName)
        data.has_schedule = safeCall(station.hasSchedule) or false
    end
    
    return data
end

-- Function to send data to server
local function sendUpdate(data)
    local json = textutils.serialiseJSON(data)
    
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

-- Function to enter assembly mode
local function enterAssemblyMode()
    local success, err = pcall(station.setAssemblyMode, true)
    if success then
        playSound("beep")
        return true, "Entered assembly mode"
    else
        playSound("error")
        return false, err or "Failed to enter assembly mode"
    end
end

-- Function to exit assembly mode
local function exitAssemblyMode()
    local success, err = pcall(station.setAssemblyMode, false)
    if success then
        playSound("beep")
        return true, "Exited assembly mode"
    else
        playSound("error")
        return false, err or "Failed to exit assembly mode"
    end
end

-- Function to assemble train
local function assembleTrain()
    -- First check if in assembly mode
    if not safeCall(station.isInAssemblyMode) then
        return false, "Not in assembly mode! Press M first"
    end
    
    playSound("assemble_start")
    
    local success, err = pcall(station.assemble)
    if success then
        playSound("assemble_complete")
        return true, "Train assembled successfully"
    else
        playSound("error")
        return false, err or "Failed to assemble train"
    end
end

-- Function to disassemble train
local function disassembleTrain()
    -- Check if in assembly mode (should not be)
    if safeCall(station.isInAssemblyMode) then
        return false, "Cannot disassemble in assembly mode!"
    end
    
    -- Check if train is present
    if not safeCall(station.isTrainPresent) then
        return false, "No train present to disassemble"
    end
    
    playSound("disassemble")
    
    local success, err = pcall(station.disassemble)
    if success then
        return true, "Train disassembled successfully"
    else
        playSound("error")
        return false, err or "Failed to disassemble train"
    end
end

-- Display functions
local function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

local function displayStatus(data, serverStatus, message)
    clearScreen()
    
    -- Header
    if term.isColor() then term.setTextColor(colors.yellow) end
    print("=== DEPOT STATION CONTROLLER ===")
    term.setTextColor(colors.white)
    print("")
    
    -- Station info
    print("Station: " .. actualStationName)
    print("Computer ID: " .. COMPUTER_ID)
    print("Speaker: " .. (useSpeaker and "Connected" or "Not found"))
    print("")
    
    -- Status
    if term.isColor() then term.setTextColor(colors.cyan) end
    print("STATUS:")
    term.setTextColor(colors.white)
    
    -- Assembly mode
    print("Assembly Mode: " .. (data.assembly_mode and "ACTIVE" or "Inactive"))
    if data.assembly_mode and term.isColor() then
        term.setTextColor(colors.orange)
        print("  Ready to assemble trains")
        term.setTextColor(colors.white)
    end
    
    -- Train presence
    print("Train Present: " .. (data.train_present and "YES" or "No"))
    if data.train_present then
        if term.isColor() then term.setTextColor(colors.green) end
        print("  Name: " .. (data.train_name or "Unnamed"))
        print("  Schedule: " .. (data.has_schedule and "Yes" or "No"))
        term.setTextColor(colors.white)
    end
    
    -- Server status
    print("")
    print("Server: " .. (serverStatus and "Connected" or "Disconnected"))
    
    -- Message
    if message then
        print("")
        if term.isColor() then term.setTextColor(colors.yellow) end
        print(">> " .. message)
        term.setTextColor(colors.white)
    end
    
    -- Controls
    print("")
    if term.isColor() then term.setTextColor(colors.lightGray) end
    print("CONTROLS:")
    print("M - Toggle Assembly Mode")
    print("A - Assemble Train (requires assembly mode)")
    print("D - Disassemble Train")
    print("R - Refresh Status")
    print("Q - Quit")
    term.setTextColor(colors.white)
end

-- Main loop
print("Starting Depot Station Controller...")
print("Station: " .. actualStationName)

-- Play startup sound
if useSpeaker then
    playTone(262, 0.1, 0.2)  -- C4
    playTone(392, 0.2, 0.2)  -- G4
end

sleep(2)

local updateTimer = os.startTimer(0)
local lastMessage = nil
local messageTimer = nil

while true do
    local event, param = os.pullEvent()
    
    if event == "timer" then
        if param == updateTimer then
            -- Regular update
            local data = getStationData()
            local serverStatus = sendUpdate(data)
            
            displayStatus(data, serverStatus, lastMessage)
            
            updateTimer = os.startTimer(UPDATE_INTERVAL)
            
        elseif param == messageTimer then
            -- Clear message after timeout
            lastMessage = nil
            messageTimer = nil
        end
        
    elseif event == "key" then
        local data = getStationData()
        
        if param == keys.q then
            -- Quit
            clearScreen()
            print("Depot controller stopped.")
            break
            
        elseif param == keys.m then
            -- Toggle assembly mode
            local success, msg
            if data.assembly_mode then
                success, msg = exitAssemblyMode()
            else
                success, msg = enterAssemblyMode()
            end
            
            lastMessage = msg
            messageTimer = os.startTimer(5)
            
            -- Force immediate update
            os.cancelTimer(updateTimer)
            updateTimer = os.startTimer(0.1)
            
        elseif param == keys.a then
            -- Assemble train
            local success, msg = assembleTrain()
            
            lastMessage = msg
            messageTimer = os.startTimer(5)
            
            -- Force immediate update
            os.cancelTimer(updateTimer)
            updateTimer = os.startTimer(0.1)
            
        elseif param == keys.d then
            -- Disassemble train
            local success, msg = disassembleTrain()
            
            lastMessage = msg
            messageTimer = os.startTimer(5)
            
            -- Force immediate update
            os.cancelTimer(updateTimer)
            updateTimer = os.startTimer(0.1)
            
        elseif param == keys.r then
            -- Refresh
            playSound("beep")
            lastMessage = "Refreshing..."
            messageTimer = os.startTimer(2)
            
            -- Force immediate update
            os.cancelTimer(updateTimer)
            updateTimer = os.startTimer(0.1)
        end
    end
end
