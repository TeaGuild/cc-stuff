-- GitHub Auto-Updater for ComputerCraft with MD5
-- Self-updating startup script that manages multiple files from GitHub
-- Uses MD5 hash comparison for reliable change detection

-- Configuration
local GITHUB_USER = "TeaGuild"
local GITHUB_REPO = "cc-stuff"
local GITHUB_BRANCH = "master"

-- Files to manage (updater first so it can self-update)
local FILES = {
    {
        github = "updater.lua",
        local_name = "startup.lua",
        description = "Auto-updater"
    },
    {
        github = "payload.lua", 
        local_name = "train_station.lua",
        description = "Train station monitor"
    }
}

-- MD5 implementation by Anavrins
local mod32 = 2^32
local bor = bit32.bor
local band = bit32.band
local bnot = bit32.bnot
local bxor = bit32.bxor
local blshift = bit32.lshift
local upack = unpack

local function lrotate(int, by)
    local s = int/(2^(32-by))
    local f = s%1
    return (s-f)+f*mod32
end

local function brshift(int, by)
    local s = int / (2^by)
    return s-s%1
end

local s = {
     7, 12, 17, 22,
     5,  9, 14, 20,
     4, 11, 16, 23,
     6, 10, 15, 21,
}

local K = {
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
}

local H = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476}

local function counter(incr)
    local t1, t2 = 0, 0
    if 0xFFFFFFFF - t1 < incr then
        t2 = t2 + 1
        t1 = incr - (0xFFFFFFFF - t1) - 1		
    else t1 = t1 + incr
    end
    return t2, t1
end

local function LE_toInt(bs, i)
    return (bs[i] or 0) + blshift((bs[i+1] or 0), 8) + blshift((bs[i+2] or 0), 16) + blshift((bs[i+3] or 0), 24)
end

local function preprocess(data)
    local len = #data
    local proc = {}
    data[#data+1] = 0x80
    while #data%64~=56 do data[#data+1] = 0 end
    local blocks = math.ceil(#data/64)
    for i = 1, blocks do
        proc[i] = {}
        for j = 1, 16 do
            proc[i][j] = LE_toInt(data, 1+((i-1)*64)+((j-1)*4))
        end
    end
    proc[blocks][16], proc[blocks][15] = counter(len*8)
    return proc
end

local function digestblock(m, C)
    local a, b, c, d = upack(C)
    for j = 0, 63 do
        local f, g, r = 0, j, brshift(j, 4)
        if r == 0 then
            f = bor(band(b, c), band(bnot(b), d))
        elseif r == 1 then
            f = bor(band(d, b), band(bnot(d), c))
            g = (5*j+1)%16
        elseif r == 2 then
            f = bxor(b, c, d)
            g = (3*j+5)%16
        elseif r == 3 then
            f = bxor(c, bor(b, bnot(d)))
            g = (7*j)%16
        end
        local dTemp = d
        a, b, c, d = dTemp, (b+lrotate((a + f + K[j+1] + m[g+1])%mod32, s[bor(blshift(r, 2), band(j, 3))+1]))%mod32, b, c
    end
    C[1] = (C[1] + a)%mod32
    C[2] = (C[2] + b)%mod32
    C[3] = (C[3] + c)%mod32
    C[4] = (C[4] + d)%mod32
    return C
end

local md5_mt = {
    __tostring = function(a) return string.char(unpack(a)) end,
    __index = {
        toHex = function(self, s) return ("%02x"):rep(#self):format(unpack(self)) end,
        isEqual = function(self, t)
            if type(t) ~= "table" then return false end
            if #self ~= #t then return false end
            local ret = 0
            for i = 1, #self do
                ret = bor(ret, bxor(self[i], t[i]))
            end
            return ret == 0
        end
    }
}

local function toBytes(t, n)
    local b = {}
    for i = 1, n do
        b[(i-1)*4+1] = band(t[i], 0xFF)
        b[(i-1)*4+2] = band(brshift(t[i], 8), 0xFF)
        b[(i-1)*4+3] = band(brshift(t[i], 16), 0xFF)
        b[(i-1)*4+4] = band(brshift(t[i], 24), 0xFF)
    end
    return setmetatable(b, md5_mt)
end

local function md5_digest(data)
    data = data or ""
    data = type(data) == "string" and {data:byte(1,-1)} or data

    data = preprocess(data)
    local C = {upack(H)}
    for i = 1, #data do C = digestblock(data[i], C) end
    return toBytes(C, 4)
end

-- Helper function to get MD5 hash as hex string
local function getFileHash(content)
    local hash = md5_digest(content)
    return hash:toHex()
end

-- Find peripherals
local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
local useMonitor = monitor ~= nil
local useSpeaker = speaker ~= nil

-- Setup monitor
if useMonitor then
    monitor.setTextScale(1)
    monitor.clear()
end

-- Audio helper functions
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
    
    if soundType == "startup" then
        -- Ascending boot sound
        playTone(262, 0.1, 0.3)  -- C4
        sleep(0.05)
        playTone(330, 0.1, 0.3)  -- E4
        sleep(0.05)
        playTone(392, 0.2, 0.3)  -- G4
        
    elseif soundType == "checking" then
        -- Quick beep
        playTone(440, 0.05, 0.2)  -- A4
        
    elseif soundType == "update_found" then
        -- Happy ascending melody
        playTone(523, 0.1, 0.3)  -- C5
        sleep(0.02)
        playTone(659, 0.1, 0.3)  -- E5
        sleep(0.02)
        playTone(784, 0.2, 0.3)  -- G5
        
    elseif soundType == "success" then
        -- Success fanfare
        playTone(523, 0.1, 0.3)  -- C5
        playTone(523, 0.1, 0.3)  -- C5
        sleep(0.05)
        playTone(784, 0.3, 0.4)  -- G5
        
    elseif soundType == "error" then
        -- Sad descending tone
        playTone(440, 0.2, 0.3)  -- A4
        sleep(0.05)
        playTone(349, 0.2, 0.3)  -- F4
        sleep(0.05)
        playTone(262, 0.3, 0.3)  -- C4
    end
end

-- Monitor display helper
local function monitorWrite(text, x, y, color)
    if not useMonitor then return end
    
    if x and y then
        monitor.setCursorPos(x, y)
    end
    
    if monitor.isColor() and color then
        monitor.setTextColor(color)
    else
        monitor.setTextColor(colors.white)
    end
    
    monitor.write(text)
    monitor.setTextColor(colors.white)
end

-- Clear monitor
local function clearMonitor()
    if not useMonitor then return end
    monitor.clear()
    monitor.setCursorPos(1, 1)
end

-- Display status on monitor
local function displayMonitorStatus(status, details)
    if not useMonitor then return end
    
    clearMonitor()
    local monWidth, monHeight = monitor.getSize()
    
    -- Title
    monitorWrite("GitHub Updater", math.floor((monWidth - 14) / 2) + 1, 1, colors.yellow)
    
    -- Status
    monitorWrite(status, 1, 3, colors.cyan)
    
    -- Details
    if details then
        local y = 5
        for i, detail in ipairs(details) do
            if y < monHeight then
                monitorWrite(detail.text, 1, y, detail.color or colors.white)
                y = y + 1
            end
        end
    end
    
    -- Footer
    monitorWrite("Computer " .. os.getComputerID(), 1, monHeight, colors.gray)
end

-- GitHub raw content URL builder
local function getGitHubURL(file)
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s",
        GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, file
    )
end

-- Read local file hash
local function getLocalHash(filename)
    if not fs.exists(filename) then
        return nil
    end
    
    local file = fs.open(filename, "r")
    if not file then
        return nil
    end
    
    local content = file.readAll()
    file.close()
    
    return getFileHash(content)
end

-- Download file from GitHub
local function downloadFile(github_file)
    local url = getGitHubURL(github_file)
    
    -- Show download status
    displayMonitorStatus("Downloading...", {{text = github_file, color = colors.yellow}})
    
    local response = http.get(url)
    
    if not response then
        return nil, "Failed to download from " .. url
    end
    
    local content = response.readAll()
    response.close()
    
    if not content or content == "" then
        return nil, "Empty response from GitHub"
    end
    
    -- Basic validation - check if it looks like Lua code
    if not (content:find("%-%-") or content:find("function") or content:find("local") or content:find("end")) then
        return nil, "Content doesn't appear to be valid Lua code"
    end
    
    return content, nil
end

-- Update a single file
local function updateFile(fileInfo)
    local localHash = getLocalHash(fileInfo.local_name)
    
    -- Download from GitHub
    local content, err = downloadFile(fileInfo.github)
    if not content then
        return false, err
    end
    
    local remoteHash = getFileHash(content)
    
    -- Debug: Show hashes
    print("  Local:  " .. (localHash or "none"))
    print("  Remote: " .. remoteHash)
    
    -- Check if update needed
    if localHash == remoteHash then
        return false, "Already up to date"
    end
    
    -- Backup existing file
    if fs.exists(fileInfo.local_name) then
        local backupName = fileInfo.local_name .. ".backup"
        if fs.exists(backupName) then
            fs.delete(backupName)
        end
        fs.copy(fileInfo.local_name, backupName)
    end
    
    -- Write new file
    local file = fs.open(fileInfo.local_name, "w")
    if not file then
        return false, "Cannot write file"
    end
    
    file.write(content)
    file.close()
    
    return true, string.format("Updated (%s -> %s)", 
        localHash and localHash:sub(1, 8) or "new", 
        remoteHash:sub(1, 8))
end

-- Quick update check with timeout
local function quickUpdateCheck()
    local updated = false
    local updaterUpdated = false
    local details = {}
    
    -- Play checking sound
    playSound("checking")
    
    -- Show initial status
    term.clear()
    term.setCursorPos(1, 1)
    if term.isColor() then term.setTextColor(colors.yellow) end
    print("GitHub Update Check")
    print("Repository: " .. GITHUB_USER .. "/" .. GITHUB_REPO)
    print("Branch: " .. GITHUB_BRANCH)
    print("")
    term.setTextColor(colors.white)
    
    displayMonitorStatus("Checking updates...", {
        {text = "Repo: " .. GITHUB_REPO, color = colors.lightGray},
        {text = "Branch: " .. GITHUB_BRANCH, color = colors.lightGray},
        {text = "Speaker: " .. (useSpeaker and "Connected" or "Not found"), color = colors.lightGray}
    })
    
    -- Check each file
    for i, fileInfo in ipairs(FILES) do
        term.setCursorPos(1, 4 + (i * 3))
        term.write(fileInfo.description .. ": ")
        
        local success, message = updateFile(fileInfo)
        
        local detailEntry = {text = fileInfo.description .. ": "}
        
        if success then
            if term.isColor() then term.setTextColor(colors.green) end
            print("Updated!")
            detailEntry.text = detailEntry.text .. "Updated!"
            detailEntry.color = colors.green
            term.setTextColor(colors.white)
            updated = true
            
            -- Check if updater itself was updated
            if fileInfo.local_name == "startup.lua" then
                updaterUpdated = true
            end
        else
            if message == "Already up to date" then
                if term.isColor() then term.setTextColor(colors.gray) end
                print("Current")
                detailEntry.text = detailEntry.text .. "Current"
                detailEntry.color = colors.gray
            else
                if term.isColor() then term.setTextColor(colors.red) end
                print("Failed")
                print("  " .. message)
                detailEntry.text = detailEntry.text .. "Failed"
                detailEntry.color = colors.red
            end
            term.setTextColor(colors.white)
        end
        
        table.insert(details, detailEntry)
    end
    
    -- Update monitor with results
    local statusText = updated and "Updates installed!" or "All files current"
    local statusDetails = details
    
    if updated then
        playSound("update_found")
        table.insert(statusDetails, {text = "", color = colors.white})
        table.insert(statusDetails, {text = "Restarting soon...", color = colors.yellow})
    end
    
    displayMonitorStatus(statusText, statusDetails)
    
    return updated, updaterUpdated
end

-- Main execution
local function main()
    -- Play startup sound
    playSound("startup")
    
    -- Perform update check
    local updated, updaterUpdated = quickUpdateCheck()
    
    -- If updater was updated, restart immediately
    if updaterUpdated then
        print("\nUpdater updated! Restarting...")
        displayMonitorStatus("Restarting...", {{text = "Updater was updated", color = colors.yellow}})
        sleep(2)
        os.reboot()
        return
    end
    
    -- Brief pause if updates were installed
    if updated then
        sleep(2)
    else
        sleep(0.5)
    end
    
    -- Check if main payload exists
    local mainScript = FILES[2].local_name  -- train_station.lua
    if not fs.exists(mainScript) then
        playSound("error")
        term.clear()
        term.setCursorPos(1, 1)
        if term.isColor() then term.setTextColor(colors.red) end
        print("ERROR: Main script not found!")
        print("Failed to download " .. mainScript)
        print("")
        print("GitHub URL:")
        print(getGitHubURL(FILES[2].github))
        term.setTextColor(colors.white)
        print("\nRetrying in 10 seconds...")
        
        displayMonitorStatus("Error!", {
            {text = "Script not found", color = colors.red},
            {text = mainScript, color = colors.orange},
            {text = "", color = colors.white},
            {text = "Retrying in 10s...", color = colors.yellow}
        })
        
        sleep(10)
        os.reboot()
        return
    end
    
    -- Clear screen and run main script
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Update monitor to show we're starting
    displayMonitorStatus("Starting...", {
        {text = "Loading " .. mainScript, color = colors.green}
    })
    
    -- Play success sound before launching
    playSound("success")
    sleep(0.5)
    clearMonitor()
    
    -- Run with error handling
    local ok, err = pcall(function()
        shell.run(mainScript)
    end)
    
    if not ok then
        -- Script crashed
        playSound("error")
        term.clear()
        term.setCursorPos(1, 1)
        if term.isColor() then term.setTextColor(colors.red) end
        print("ERROR: Main script crashed!")
        term.setTextColor(colors.white)
        print(err)
        print("\nRebooting in 10 seconds...")
        
        displayMonitorStatus("Crashed!", {
            {text = "Script error", color = colors.red},
            {text = "", color = colors.white},
            {text = "Rebooting in 10s...", color = colors.yellow}
        })
        
        sleep(10)
        os.reboot()
    end
end

-- Emergency error handler
local ok, err = pcall(main)
if not ok then
    playSound("error")
    if term.isColor() then term.setTextColor(colors.red) end
    print("CRITICAL ERROR in updater:")
    term.setTextColor(colors.white)
    print(err)
    print("\nRebooting in 10 seconds...")
    
    if useMonitor then
        displayMonitorStatus("CRITICAL ERROR", {
            {text = "Updater crashed!", color = colors.red},
            {text = "", color = colors.white},
            {text = "Check terminal", color = colors.orange}
        })
    end
    
    sleep(10)
    os.reboot()
end
