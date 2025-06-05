-- GitHub Auto-Updater for ComputerCraft with Manifest Support
-- Self-updating startup script that manages multiple scripts from GitHub
-- Uses MD5 hash comparison and manifest-based script selection

-- Configuration
local GITHUB_USER = "TeaGuild"
local GITHUB_REPO = "cc-stuff"
local GITHUB_BRANCH = "master"
local CONFIG_FILE = ".updater_config"
local MANIFEST_URL = "manifest.json"

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
        
    elseif soundType == "select" then
        -- Selection beep
        playTone(600, 0.05, 0.2)
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

-- Config management
local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        return {}
    end
    
    local file = fs.open(CONFIG_FILE, "r")
    local content = file.readAll()
    file.close()
    
    return textutils.unserialise(content) or {}
end

local function saveConfig(config)
    local file = fs.open(CONFIG_FILE, "w")
    file.write(textutils.serialise(config))
    file.close()
end

-- Load cached manifest
local function loadCachedManifest()
    local MANIFEST_CACHE = ".manifest_cache"
    if not fs.exists(MANIFEST_CACHE) then
        return nil
    end
    
    local file = fs.open(MANIFEST_CACHE, "r")
    local content = file.readAll()
    file.close()
    
    return textutils.unserialiseJSON(content)
end

-- Save manifest to cache
local function saveManifestCache(manifest)
    local MANIFEST_CACHE = ".manifest_cache"
    local file = fs.open(MANIFEST_CACHE, "w")
    file.write(textutils.serialiseJSON(manifest))
    file.close()
end

-- Download and parse manifest
local function downloadManifest(checkOnly)
    local url = getGitHubURL(MANIFEST_URL)
    
    -- Download manifest
    local response = http.get(url)
    if not response then
        return nil, "Failed to download manifest", false
    end
    
    local content = response.readAll()
    response.close()
    
    -- Parse manifest
    local manifest = textutils.unserialiseJSON(content)
    if not manifest or not manifest.scripts then
        return nil, "Invalid manifest format", false
    end
    
    -- Check if manifest has changed
    local cachedManifest = loadCachedManifest()
    local manifestChanged = false
    
    if cachedManifest then
        -- Compare manifest hashes
        local oldHash = getFileHash(textutils.serialiseJSON(cachedManifest))
        local newHash = getFileHash(textutils.serialiseJSON(manifest))
        manifestChanged = (oldHash ~= newHash)
        
        if manifestChanged and not checkOnly then
            print("Manifest updated - new scripts may be available!")
            sleep(2)
        end
    else
        manifestChanged = true
    end
    
    -- Save manifest if not in check-only mode
    if not checkOnly and manifestChanged then
        saveManifestCache(manifest)
    end
    
    return manifest, nil, manifestChanged
end

-- Script selection menu
local function selectScript(manifest)
    term.clear()
    term.setCursorPos(1, 1)
    
    if term.isColor() then term.setTextColor(colors.yellow) end
    print("=== Script Selection ===")
    term.setTextColor(colors.white)
    print("")
    
    -- Group by category
    local categories = {}
    for _, script in ipairs(manifest.scripts) do
        local cat = script.category or "Other"
        if not categories[cat] then
            categories[cat] = {}
        end
        table.insert(categories[cat], script)
    end
    
    -- Display options
    local options = {}
    local y = 3
    
    for category, scripts in pairs(categories) do
        if term.isColor() then term.setTextColor(colors.cyan) end
        print(category .. ":")
        term.setTextColor(colors.white)
        
        for _, script in ipairs(scripts) do
            table.insert(options, script)
            print("  " .. #options .. ". " .. script.name)
            if term.isColor() then term.setTextColor(colors.gray) end
            print("     " .. script.description)
            term.setTextColor(colors.white)
        end
        print("")
    end
    
    -- Monitor display
    if useMonitor then
        displayMonitorStatus("Select Script", {
            {text = "Check terminal", color = colors.yellow},
            {text = "for options", color = colors.yellow}
        })
    end
    
    -- Get selection
    print("")
    term.write("Select script (1-" .. #options .. "): ")
    
    local selection = nil
    while not selection do
        local input = read()
        local num = tonumber(input)
        
        if num and num >= 1 and num <= #options then
            selection = options[num]
            playSound("select")
        else
            if term.isColor() then term.setTextColor(colors.red) end
            print("Invalid selection. Try again: ")
            term.setTextColor(colors.white)
            term.write("Select script (1-" .. #options .. "): ")
        end
    end
    
    return selection
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
    
    local response = http.get(url)
    
    if not response then
        return nil, "Failed to download from " .. url
    end
    
    local content = response.readAll()
    response.close()
    
    if not content or content == "" then
        return nil, "Empty response from GitHub"
    end
    
    return content, nil
end

-- Update a single file
local function updateFile(github_file, local_name, description)
    local localHash = getLocalHash(local_name)
    
    -- Download from GitHub
    local content, err = downloadFile(github_file)
    if not content then
        return false, err
    end
    
    local remoteHash = getFileHash(content)
    
    -- Debug: Show hashes (only if terminal is available)
    if term.current() then
        local _, y = term.getCursorPos()
        if y < 20 then  -- Only print if there's room on screen
            print("  Local:  " .. (localHash or "none"))
            print("  Remote: " .. remoteHash)
        end
    end
    
    -- Check if update needed
    if localHash == remoteHash then
        return false, "Already up to date"
    end
    
    -- Backup existing file
    if fs.exists(local_name) then
        local backupName = local_name .. ".backup"
        if fs.exists(backupName) then
            fs.delete(backupName)
        end
        fs.copy(local_name, backupName)
    end
    
    -- Write new file
    local file = fs.open(local_name, "w")
    if not file then
        return false, "Cannot write file"
    end
    
    file.write(content)
    file.close()
    
    return true, string.format("Updated (%s -> %s)", 
        localHash and localHash:sub(1, 8) or "new", 
        remoteHash:sub(1, 8))
end

-- Quick update check
local function quickUpdateCheck(selectedScript, checkOnly)
    local updated = false
    local updaterUpdated = false
    local details = {}
    
    -- Don't play sound if check-only mode
    if not checkOnly then
        playSound("checking")
    end
    
    -- Show initial status
    if not checkOnly then
        term.clear()
        term.setCursorPos(1, 1)
        if term.isColor() then term.setTextColor(colors.yellow) end
        print("GitHub Update Check")
        print("Selected: " .. selectedScript.name)
        print("")
        term.setTextColor(colors.white)
        
        displayMonitorStatus("Checking updates...", {
            {text = selectedScript.name, color = colors.cyan},
            {text = "Repo: " .. GITHUB_REPO, color = colors.lightGray}
        })
    end
    
    -- Files to check
    local filesToCheck = {
        {
            github = "updater.lua",
            local_name = "startup.lua",
            description = "Updater"
        },
        {
            github = selectedScript.file,
            local_name = selectedScript.local_name,
            description = selectedScript.name
        }
    }
    
    -- Add manifest to check list (but not in check-only mode from other scripts)
    if not checkOnly then
        table.insert(filesToCheck, {
            github = "manifest.json",
            local_name = ".manifest_cache",
            description = "Manifest"
        })
    end
    
    -- Check each file
    for i, fileInfo in ipairs(filesToCheck) do
        if not checkOnly then
            term.setCursorPos(1, 3 + (i * 3))
            term.write(fileInfo.description .. ": ")
        end
        
        local success, message
        
        if checkOnly then
            -- In check-only mode, just check if update is needed without installing
            success, message = checkFileNeedsUpdate(fileInfo.github, fileInfo.local_name, checkOnly)
        else
            -- In normal mode, actually update the file
            success, message = updateFile(fileInfo.github, fileInfo.local_name, fileInfo.description, checkOnly)
        end
        
        if success then
            if not checkOnly then
                if term.isColor() then term.setTextColor(colors.green) end
                print("Updated!")
                term.setTextColor(colors.white)
            end
            updated = true
            
            -- Check if updater itself was updated
            if fileInfo.local_name == "startup.lua" then
                updaterUpdated = true
            end
        else
            if not checkOnly then
                if message == "Already up to date" then
                    if term.isColor() then term.setTextColor(colors.gray) end
                    print("Current")
                else
                    if term.isColor() then term.setTextColor(colors.red) end
                    print("Failed: " .. message)
                end
                term.setTextColor(colors.white)
            end
        end
        
        table.insert(details, {
            text = fileInfo.description .. ": " .. (success and "Updated!" or "Current"),
            color = success and colors.green or colors.gray
        })
    end
    
    -- Update monitor with results
    if not checkOnly then
        local statusText = updated and "Updates installed!" or "All files current"
        
        if updated then
            playSound("update_found")
            table.insert(details, {text = "", color = colors.white})
            table.insert(details, {text = "Restarting soon...", color = colors.yellow})
        end
        
        displayMonitorStatus(statusText, details)
    end
    
    return updated, updaterUpdated
end

-- Main execution
local function main(...)
    local args = {...}
    local checkOnly = args[1] == "check"
    
    -- Play startup sound (unless in check-only mode)
    if not checkOnly then
        playSound("startup")
    end
    
    -- Check for selection key (skip in check-only mode)
    local changeSelection = false
    if not checkOnly then
        print("Press S within 2 seconds to change script selection...")
        local timer = os.startTimer(2)
        
        while true do
            local event, param = os.pullEvent()
            if event == "timer" and param == timer then
                break
            elseif event == "key" and (param == keys.s or param == keys.S) then
                changeSelection = true
                break
            end
        end
    end
    
    -- Load config
    local config = loadConfig()
    
    -- Download manifest
    if not checkOnly then
        print("\nDownloading manifest...")
    end
    local manifest, err, manifestChanged = downloadManifest(checkOnly)
    if not manifest then
        if not checkOnly then
            playSound("error")
            print("Failed to download manifest: " .. err)
            
            -- Try to use cached manifest
            manifest = loadCachedManifest()
            if manifest then
                print("Using cached manifest...")
                sleep(1)
            else
                sleep(5)
                os.reboot()
                return false
            end
        else
            return false
        end
    end
    
    -- Check if we should prompt for new selection due to manifest changes
    local forceSelection = false
    if manifestChanged and config.selected_script then
        -- Check if our selected script still exists
        local scriptExists = false
        for _, script in ipairs(manifest.scripts) do
            if script.id == config.selected_script then
                scriptExists = true
                break
            end
        end
        
        if not scriptExists then
            print("Selected script no longer exists!")
            forceSelection = true
        elseif not checkOnly then
            -- Count new scripts
            local cachedManifest = loadCachedManifest()
            local newScripts = 0
            if cachedManifest then
                for _, script in ipairs(manifest.scripts) do
                    local found = false
                    for _, oldScript in ipairs(cachedManifest.scripts) do
                        if script.id == oldScript.id then
                            found = true
                            break
                        end
                    end
                    if not found then
                        newScripts = newScripts + 1
                    end
                end
            end
            
            if newScripts > 0 then
                print("")
                if term.isColor() then term.setTextColor(colors.lime) end
                print(newScripts .. " new script(s) available!")
                print("Press S to view new options...")
                term.setTextColor(colors.white)
                
                -- Give extra time to press S
                local timer = os.startTimer(3)
                while true do
                    local event, param = os.pullEvent()
                    if event == "timer" and param == timer then
                        break
                    elseif event == "key" and (param == keys.s or param == keys.S) then
                        changeSelection = true
                        break
                    end
                end
            end
        end
    end
    
    -- Select script if needed
    local selectedScript = nil
    
    if not checkOnly and (changeSelection or forceSelection or not config.selected_script) then
        selectedScript = selectScript(manifest)
        config.selected_script = selectedScript.id
        saveConfig(config)
        print("\nSelection saved: " .. selectedScript.name)
        sleep(1)
    else
        -- Find selected script in manifest
        for _, script in ipairs(manifest.scripts) do
            if script.id == config.selected_script then
                selectedScript = script
                break
            end
        end
        
        -- Fallback to default if not found
        if not selectedScript then
            for _, script in ipairs(manifest.scripts) do
                if script.id == manifest.default then
                    selectedScript = script
                    break
                end
            end
        end
        
        -- Last resort - first script
        if not selectedScript then
            selectedScript = manifest.scripts[1]
        end
    end
    
    -- Perform update check
    local updated, updaterUpdated = quickUpdateCheck(selectedScript, checkOnly)
    
    -- If in check-only mode, return the update status
    if checkOnly then
        return updated
    end
    
    -- If updater was updated, restart immediately
    if updaterUpdated then
        print("\nUpdater updated! Restarting...")
        sleep(2)
        os.reboot()
        return true  -- This won't execute due to reboot, but good practice
    end
    
    -- Brief pause if updates were installed
    if updated then
        sleep(2)
    else
        sleep(0.5)
    end
    
    -- Check if main script exists
    if not fs.exists(selectedScript.local_name) then
        playSound("error")
        term.clear()
        term.setCursorPos(1, 1)
        if term.isColor() then term.setTextColor(colors.red) end
        print("ERROR: Script not found!")
        print("Failed to download " .. selectedScript.local_name)
        term.setTextColor(colors.white)
        print("\nRetrying in 10 seconds...")
        
        displayMonitorStatus("Error!", {
            {text = "Script not found", color = colors.red},
            {text = selectedScript.local_name, color = colors.orange}
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
        {text = selectedScript.name, color = colors.green}
    })
    
    -- Play success sound before launching
    playSound("success")
    sleep(0.5)
    clearMonitor()
    
    -- Run with error handling
    local ok, err = pcall(function()
        shell.run(selectedScript.local_name)
    end)
    
    if not ok then
        -- Script crashed
        playSound("error")
        term.clear()
        term.setCursorPos(1, 1)
        if term.isColor() then term.setTextColor(colors.red) end
        print("ERROR: Script crashed!")
        term.setTextColor(colors.white)
        print(err)
        print("\nRebooting in 10 seconds...")
        
        displayMonitorStatus("Crashed!", {
            {text = "Script error", color = colors.red},
            {text = selectedScript.name, color = colors.orange}
        })
        
        sleep(10)
        os.reboot()
    end
    
    -- Normal execution completed
    return false
end

-- Emergency error handler and return value handling
local ok, result = pcall(main, ...)
if not ok then
    playSound("error")
    if term.isColor() then term.setTextColor(colors.red) end
    print("CRITICAL ERROR in updater:")
    term.setTextColor(colors.white)
    print(result)  -- 'result' contains the error message when pcall fails
    print("\nRebooting in 10 seconds...")
    
    if useMonitor then
        displayMonitorStatus("CRITICAL ERROR", {
            {text = "Updater crashed!", color = colors.red}
        })
    end
    
    sleep(10)
    os.reboot()
else
    -- If we were in check-only mode, return the result
    if ({...})[1] == "check" then
        return result
    end
end
