-- Hello World Demo Script
-- Simple example showing monitor output and basic interactivity

-- Find peripherals
local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")

-- Colors for rainbow effect
local rainbowColors = {
    colors.red,
    colors.orange,
    colors.yellow,
    colors.lime,
    colors.green,
    colors.cyan,
    colors.lightBlue,
    colors.blue,
    colors.purple,
    colors.magenta,
    colors.pink
}

-- Play a tone if speaker is available
local function playTone(freq, duration)
    if not speaker then return end
    
    local sampleRate = 48000
    local samples = math.floor(sampleRate * duration)
    local buffer = {}
    
    for i = 1, samples do
        local t = (i - 1) / sampleRate
        local value = math.sin(2 * math.pi * freq * t) * 127 * 0.3
        buffer[i] = math.floor(value)
    end
    
    speaker.playAudio(buffer)
end

-- Main display function
local function displayHelloWorld()
    -- Terminal display
    term.clear()
    term.setCursorPos(1, 1)
    if term.isColor() then term.setTextColor(colors.yellow) end
    print("=== Hello World Demo ===")
    term.setTextColor(colors.white)
    print("")
    print("Computer ID: " .. os.getComputerID())
    print("Monitor: " .. (monitor and "Connected" or "Not found"))
    print("Speaker: " .. (speaker and "Connected" or "Not found"))
    print("")
    print("Controls:")
    print("- Space: Play sound")
    print("- C: Clear monitor")
    print("- R: Rainbow mode")
    print("- Q: Quit")
    
    -- Monitor display
    if monitor then
        monitor.setTextScale(2)
        monitor.clear()
        
        local width, height = monitor.getSize()
        local text = "Hello World!"
        
        -- Center the text
        local x = math.floor((width - #text) / 2) + 1
        local y = math.floor(height / 2)
        
        monitor.setCursorPos(x, y)
        if monitor.isColor() then
            monitor.setTextColor(colors.yellow)
        end
        monitor.write(text)
        
        -- Add computer info
        monitor.setTextScale(1)
        monitor.setCursorPos(1, height)
        monitor.setTextColor(colors.gray)
        monitor.write("Computer " .. os.getComputerID())
    end
end

-- Rainbow animation
local function rainbowMode()
    if not monitor or not monitor.isColor() then
        print("Rainbow mode requires a color monitor!")
        return
    end
    
    print("\nRainbow mode! Press any key to stop...")
    
    monitor.setTextScale(2)
    local width, height = monitor.getSize()
    local text = "Hello World!"
    local x = math.floor((width - #text) / 2) + 1
    local y = math.floor(height / 2)
    
    local colorIndex = 1
    local timer = os.startTimer(0.1)
    
    while true do
        local event, param = os.pullEvent()
        
        if event == "timer" and param == timer then
            monitor.setCursorPos(x, y)
            monitor.setTextColor(rainbowColors[colorIndex])
            monitor.write(text)
            
            colorIndex = colorIndex + 1
            if colorIndex > #rainbowColors then
                colorIndex = 1
            end
            
            timer = os.startTimer(0.1)
        elseif event == "key" then
            break
        end
    end
    
    displayHelloWorld()
end

-- Main program
displayHelloWorld()

-- Play welcome sound
if speaker then
    playTone(440, 0.1)  -- A4
    sleep(0.05)
    playTone(554, 0.1)  -- C#5
    sleep(0.05)
    playTone(659, 0.2)  -- E5
end

-- Main loop
while true do
    local event, key = os.pullEvent("key")
    
    if key == keys.q then
        -- Quit
        term.clear()
        term.setCursorPos(1, 1)
        print("Goodbye!")
        
        if monitor then
            monitor.clear()
            monitor.setCursorPos(1, 1)
            monitor.write("Goodbye!")
        end
        
        -- Play goodbye sound
        if speaker then
            playTone(659, 0.1)  -- E5
            sleep(0.05)
            playTone(440, 0.2)  -- A4
        end
        
        sleep(1)
        break
        
    elseif key == keys.space then
        -- Play sound
        if speaker then
            -- Play a little melody
            local notes = {523, 587, 659, 698, 784}  -- C5, D5, E5, F5, G5
            for _, note in ipairs(notes) do
                playTone(note, 0.1)
                sleep(0.05)
            end
        else
            print("No speaker connected!")
        end
        
    elseif key == keys.c then
        -- Clear monitor
        if monitor then
            monitor.clear()
            print("Monitor cleared!")
        end
        
    elseif key == keys.r then
        -- Rainbow mode
        rainbowMode()
    end
end
