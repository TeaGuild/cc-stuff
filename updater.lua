-- GitHub Auto-Updater for ComputerCraft
-- Self-updating startup script that manages multiple files from GitHub
-- Uses hash comparison for reliable change detection

-- Configuration
local GITHUB_USER = "TeaGuild"
local GITHUB_REPO = "cc-stuff"
local GITHUB_BRANCH = "master"  -- Changed from "main" to "master"

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

-- Find monitor if available
local monitor = peripheral.find("monitor")
local useMonitor = monitor ~= nil

-- Setup monitor
if useMonitor then
    monitor.setTextScale(1)
    monitor.clear()
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

-- Calculate file hash
local function getFileHash(content)
    -- Simple but effective hash function
    local hash = 0
    for i = 1, #content do
        local byte = string.byte(content, i)
        hash = ((hash * 31) + byte) % 2147483647
    end
    return tostring(hash)
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
    
    return true, string.format("Updated (hash: %s -> %s)", localHash or "new", remoteHash)
end

-- Quick update check with timeout
local function quickUpdateCheck()
    local updated = false
    local updaterUpdated = false
    local details = {}
    
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
        {text = "Branch: " .. GITHUB_BRANCH, color = colors.lightGray}
    })
    
    -- Check each file
    for i, fileInfo in ipairs(FILES) do
        term.setCursorPos(1, 4 + i)
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
        table.insert(statusDetails, {text = "", color = colors.white})
        table.insert(statusDetails, {text = "Restarting soon...", color = colors.yellow})
    end
    
    displayMonitorStatus(statusText, statusDetails)
    
    return updated, updaterUpdated
end

-- Main execution
local function main()
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
    
    sleep(0.5)
    clearMonitor()
    
    -- Run with error handling
    local ok, err = pcall(function()
        shell.run(mainScript)
    end)
    
    if not ok then
        -- Script crashed
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
